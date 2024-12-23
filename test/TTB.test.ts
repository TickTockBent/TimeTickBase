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
  const STAKE_UNIT = ethers.parseUnits("3600", 18); // One stake hour

  beforeEach(async function () {
    [deployer, devFund, stabilityPool, user1, user2] = await ethers.getSigners();

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

    // 2) Simulate 2 hours passing (7200 seconds)
    const timeIncrease = ONE_HOUR_SECONDS * 2;
    await increaseTime(timeIncrease);

    // 3) Call mintBatch
    // No stakers => dev gets 70%, stability gets 30%
    await timeToken.mintBatch();

    // 4) Check minted amounts
    // The contract mints 1 TTB/second * 7200 seconds = 7200 TTB
    // Dev gets 70% => 5040 TTB, Stability gets 30% => 2160 TTB
    const devBalance = await timeToken.balanceOf(await devFund.getAddress());
    const stabilityBalance = await timeToken.balanceOf(
      await stabilityPool.getAddress()
    );

    const totalTokens = ethers.toBigInt(timeIncrease) * ethers.parseUnits("1", 18);
    const expectedDevBalance = (totalTokens * 70n) / 100n;
    const expectedStabilityBalance = (totalTokens * 30n) / 100n;
    
    expect(devBalance).to.be.closeTo(expectedDevBalance, ethers.parseUnits("2", 18));
    expect(stabilityBalance).to.be.closeTo(expectedStabilityBalance, ethers.parseUnits("2", 18));

    // 5) Time check
    const lastMintTime = await timeToken.lastMintTime();
    const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
    expect(Math.abs(Number(lastMintTime) - blockTimestamp)).to.be.lt(5);
  });

  it("Scenario 2: Dev transfers tokens to users so they can stake; minted tokens flow naturally", async () => {
    // 1) Let 2 hours pass & mint once with no stakers
    await increaseTime(ONE_HOUR_SECONDS * 2);
    await timeToken.mintBatch();

    // 2) Record initial balances
    const devBalBefore = await timeToken.balanceOf(await devFund.getAddress());
    const stabilityBalBefore = await timeToken.balanceOf(
      await stabilityPool.getAddress()
    );
    expect(devBalBefore).to.be.gt(0);
    expect(stabilityBalBefore).to.be.gt(0);

    // 3) Dev transfers smaller amounts to users
    const devFundContract = timeToken.connect(devFund);
    await devFundContract.transfer(
      await user1.getAddress(),
      ethers.parseUnits("500", 18)
    );
    await devFundContract.transfer(
      await user2.getAddress(),
      ethers.parseUnits("500", 18)
    );

    // 4) Let more time pass to accumulate tokens
    await increaseTime(ONE_HOUR_SECONDS * 2);
    // Dev still gets 70% because users haven't staked yet
    await timeToken.mintBatch();

    // Transfer more tokens to enable staking
    await devFundContract.transfer(
      await user1.getAddress(),
      ethers.parseUnits("3500", 18)
    );
    await devFundContract.transfer(
      await user2.getAddress(),
      ethers.parseUnits("3500", 18)
    );

    // Users stake
    const user1Token = timeToken.connect(user1);
    const user2Token = timeToken.connect(user2);
    await user1Token.stake(1); // stake 1 hour
    await user2Token.stake(1); // stake 1 hour

    // 5) Move time forward, then mint again
    await increaseTime(ONE_HOUR_SECONDS);
    // Dev still gets 70% because this is first batch after staking (lastHours = 0)
    await timeToken.mintBatch();

    // 6) Check balances
    const user1Balance = await timeToken.balanceOf(await user1.getAddress());
    const user2Balance = await timeToken.balanceOf(await user2.getAddress());
    const devBalAfter = await timeToken.balanceOf(await devFund.getAddress());

    // Calculate expected dev balance using BigInt arithmetic:
    // First mint (2hr): 70% of 7200 tokens = 5040
    // Second mint (2hr): 70% of 7200 tokens = 5040
    // Third mint (1hr): 70% of 3600 tokens = 2520 (still 70% because first batch after staking)
    // Less transfers: 8000 tokens (500+500+3500+3500)
    const secondMintBigInt = ethers.toBigInt(ethers.parseUnits("5040", 18));  // 70% of 7200
    const thirdMintBigInt = ethers.toBigInt(ethers.parseUnits("2520", 18));   // 70% of 3600
    const totalTransfersBigInt = ethers.toBigInt(ethers.parseUnits("8000", 18)); // Total transfers
    const devBalBeforeBigInt = ethers.toBigInt(devBalBefore);

    const expectedFinalDevBalance = devBalBeforeBigInt + secondMintBigInt + thirdMintBigInt - totalTransfersBigInt;

    expect(devBalAfter).to.be.closeTo(expectedFinalDevBalance, ethers.parseUnits("10", 18));
    expect(user1Balance).to.be.gt(0);
    expect(user2Balance).to.be.gt(0);

    console.log("User1 final balance:", user1Balance.toString());
    console.log("User2 final balance:", user2Balance.toString());
    console.log("Dev final balance:", devBalAfter.toString());
  });

  it("Scenario 3: Validate supply (mintBatchValidated) to ensure final supply matches time-based emission", async () => {
    // 1) Let some time pass, no stakers => dev/stability get tokens
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // 2) Let more time pass
    await increaseTime(ONE_HOUR_SECONDS);

    // 3) Call validated mint
    await timeToken.mintBatchValidated();

    // 4) Check supply validation
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

    expect(Number(diff)).to.be.lessThanOrEqual(1e14);
  });

  it("Scenario 4: Multiple stakers, repeated batch calls, final alignment with validated mint", async () => {
    // 1) No stakers, pass 2 hours, dev/stability get tokens
    await increaseTime(ONE_HOUR_SECONDS * 2);
    await timeToken.mintBatch();

    // 2) Dev => user1 tokens, user1 stakes
    const devFundToken = timeToken.connect(devFund);
    await devFundToken.transfer(
      await user1.getAddress(),
      ethers.parseUnits("1000", 18)
    );

    // Wait for more tokens to accumulate
    await increaseTime(ONE_HOUR_SECONDS * 2);
    await timeToken.mintBatch();

    // Transfer more and stake
    await devFundToken.transfer(
      await user1.getAddress(),
      ethers.parseUnits("3000", 18)
    );
    await timeToken.connect(user1).stake(1);

    // 3) Pass time, unvalidated mint => user1 gets portion
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // 4) user2 also stakes
    await devFundToken.transfer(
      await user2.getAddress(),
      ethers.parseUnits("1000", 18)
    );
    
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();
    
    await devFundToken.transfer(
      await user2.getAddress(),
      ethers.parseUnits("3000", 18)
    );
    await timeToken.connect(user2).stake(1);

    // 5) Pass time again, unvalidated mint
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // 6) Now do a validated mint
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatchValidated();

    // 7) Check final supply alignment
    const [valid] = await timeToken.validateSupply();
    expect(valid).to.equal(true);
  });
});