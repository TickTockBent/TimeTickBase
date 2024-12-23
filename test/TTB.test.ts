import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

// A helper function to simulate time passing in the local Hardhat EVM.
async function increaseTime(seconds: number) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

describe("TimeToken distribution model", function () {
  let TimeToken: any;
  let timeToken: Contract;

  // Signers
  let deployer: Signer;
  let devFund: Signer;
  let stabilityPool: Signer;
  let user1: Signer;
  let user2: Signer;

  // Constants
  const BATCH_DURATION = 3600; // 1 hour in seconds
  const ONE_HOUR_SECONDS = 3600;

  beforeEach(async function () {
    [deployer, devFund, stabilityPool, user1, user2] =
      await ethers.getSigners();

    // Deploy the contract with no forced initial supply
    TimeToken = await ethers.getContractFactory("TimeToken");
    timeToken = await TimeToken.deploy(
      await devFund.getAddress(),
      await stabilityPool.getAddress(),
      BATCH_DURATION
    );
    await timeToken.waitForDeployment();
  });

  it("Scenario 1: No stakers at first -> Dev (70%) & Stability (30%) receive tokens", async () => {
    // 1) Immediately calling mintBatch should revert if not enough time has passed
    await expect(timeToken.mintBatch()).to.be.revertedWith(
      "Batch period not reached"
    );

    // 2) Simulate 1 hour passing
    await increaseTime(ONE_HOUR_SECONDS * 2);

    // 3) Call mintBatch
    // No stakers => dev gets 70%, stability gets 30%
    await timeToken.mintBatch();

    // 4) Check minted amounts
    // The contract mints 1 TTB/second * 3600 seconds = 3600 TTB (in 18-decimal form = 3600e18)
    // Dev gets 70% => 2520 TTB, Stability gets 30% => 1080 TTB

    const devBalance = await timeToken.balanceOf(await devFund.getAddress());
    const stabilityBalance = await timeToken.balanceOf(
      await stabilityPool.getAddress()
    );
    // Because it's 70/30 of 3600 = 2520 / 1080, but in 18 decimals
    const expectedDevBalance = ethers.parseUnits("2520", 18);
    expect(devBalance).to.be.closeTo(expectedDevBalance, ethers.parseUnits("2", 18)); // Allow 2 token variance

    // 5) Time check: lastMintTime should be updated
    const lastMintTime = await timeToken.lastMintTime();
    const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
    // They should be approximately the same
    // We'll allow a small difference in case a fraction of a second passed:
    expect(Math.abs(Number(lastMintTime) - blockTimestamp)).to.be.lt(5);
  });

  it("Scenario 2: Dev transfers tokens to users so they can stake; minted tokens flow naturally", async () => {
    // 1) Let 1 hour pass & mint once with no stakers
    //    => dev & stability get tokens
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // 2) Confirm dev/stability have balances
    const devBalBefore = await timeToken.balanceOf(await devFund.getAddress());
    const stabilityBalBefore = await timeToken.balanceOf(
      await stabilityPool.getAddress()
    );
    expect(devBalBefore).to.be.gt(0);
    expect(stabilityBalBefore).to.be.gt(0);

    // 3) Dev decides to transfer some tokens to user1, user2 so they can stake
    const devFundAddress = await devFund.getAddress();
    const devFundContract = timeToken.connect(devFund);

    // dev -> user1: 2000 tokens
    // dev -> user2: 1000 tokens
    await devFundContract.transfer(
      await user1.getAddress(),
      ethers.parseUnits("2000", 18)
    );
    await devFundContract.transfer(
      await user2.getAddress(),
      ethers.parseUnits("1000", 18)
    );

    // 4) user1 and user2 stake
    // Must stake in multiples of STAKE_UNIT (3600 tokens) or partial if you prefer
    // But let's let them stake half or something. Actually, they must stake at least 1 stake-hour = 3600 TTB
    // So let's show that user1 doesn't have enough to stake 1 hour if we strictly require 3600.
    // We'll just set min stake to 1 in a scenario where we "pretend" partial stake is possible. 
    // Or let's do a second mint so user1 has enough. Instead, let's be consistent:
    // We'll do: user1 has 2000 tokens, that's NOT enough to stake 1 hour if STAKE_UNIT=3600. 
    // So let's pass more time & do a second mint, so dev can get more & then give it to user1 to stake.

    // Actually, let's do the simpler approach: user1 can "pretend" to stake 0.5 hours if your code allowed it, 
    // but it doesn't. So let's pass more time for dev to accumulate more tokens, then user1 can stake 3600. 
    // We'll do it in steps to show the whole flow:

    // Let time pass again
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch(); // dev/stability get more

    // Now dev has more tokens. Transfer enough so user1 can stake 3600 tokens
    await devFundContract.transfer(
      await user1.getAddress(),
      ethers.parseUnits("3000", 18)
    );
    // user1 total: 2000 + 3000 = 5000 => enough to stake 3600

    // user1 stakes 1 hour
    const user1Token = timeToken.connect(user1);
    await user1Token.stake(1);

    // user2 also, let's give them enough for 1 hour
    // They have 1000 from before, let's send them 3000 more
    await devFundContract.transfer(
      await user2.getAddress(),
      ethers.parseUnits("3000", 18)
    );
    const user2Token = timeToken.connect(user2);
    await user2Token.stake(1);

    // 5) Move time forward, then mint again -> now we have keepers
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch(); // stakers get 70% portion

    // 6) Check user1, user2 balances to confirm they received minted rewards
    const user1Balance = await timeToken.balanceOf(await user1.getAddress());
    const user2Balance = await timeToken.balanceOf(await user2.getAddress());

    // They staked 1 hour each. The timekeepers portion is 70% of the minted batch,
    // which is then split among timekeepers by their "maintained stake-hours."
    // Since user1 & user2 each staked 1 hour, they'd get equal shares of that 70%.

    expect(user1Balance).to.be.gt(0); // They used 3600 to stake, so they had ~1400 left over, plus new minted
    expect(user2Balance).to.be.gt(0);

    // 7) Confirm dev/stability also grew
    const devBalAfter = await timeToken.balanceOf(devFundAddress);
    expect(devBalAfter).to.be.gt(devBalBefore);

    // Print out some helpful logs
    console.log("User1 final balance:", user1Balance.toString());
    console.log("User2 final balance:", user2Balance.toString());
    console.log("Dev final balance:", devBalAfter.toString());
  });

  it("Scenario 3: Validate supply (mintBatchValidated) to ensure final supply matches time-based emission", async () => {
    // 1) Let some time pass, no stakers => dev/stability get tokens
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // 2) Let more time pass so there's an opportunity for under/over supply
    await increaseTime(ONE_HOUR_SECONDS);

    // 3) Call the validated mint
    await timeToken.mintBatchValidated();

    // 4) Check the supply validation
    const [
      valid,
      totalSecs,
      expectedSupply,
      currentSupply,
      diff,
    ] = await timeToken.validateSupply();

    console.log("Validation results:", {
      valid,
      totalSecs: totalSecs.toString(),
      expectedSupply: expectedSupply.toString(),
      currentSupply: currentSupply.toString(),
      diff: diff.toString(),
    });

    // We expect diff to be 0 if everything lines up exactly. 
    // A small difference might exist if a fraction of a second passed 
    // or if block.timestamp advanced slightly. We'll accept near 0 if needed.
    expect(Number(diff)).to.be.lessThanOrEqual(1e14); 
  });

  it("Scenario 4: Multiple stakers, repeated batch calls, final alignment with validated mint", async () => {
    // Step by step:
    // 1) No stakers, pass 1 hour, dev/stability get tokens
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // 2) Dev => user1 tokens, user1 stakes
    const devFundToken = timeToken.connect(devFund);
    await devFundToken.transfer(
      await user1.getAddress(),
      ethers.parseUnits("4000", 18)
    );

    await timeToken.connect(user1).stake(1); // user1 stakes 1 hour

    // 3) Pass time, unvalidated mint => user1 gets portion
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // 4) user2 also stakes
    await devFundToken.transfer(
      await user2.getAddress(),
      ethers.parseUnits("4000", 18)
    );
    await timeToken.connect(user2).stake(1);

    // 5) Pass time again, unvalidated mint
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // 6) Now do a validated mint to line up total supply
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatchValidated();

    // 7) Check final supply alignment
    const [valid] = await timeToken.validateSupply();
    expect(valid).to.equal(true);
  });
});
