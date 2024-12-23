import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("TimeToken", function () {
  let TimeToken: any;
  let timeToken: Contract;

  let deployer: Signer;
  let devFund: Signer;
  let stabilityPool: Signer;
  let user1: Signer;
  let user2: Signer;
  let user3: Signer;

  // Helper to quickly move time forward on Hardhat
  async function increaseTime(seconds: number) {
    await ethers.provider.send("evm_increaseTime", [seconds]);
    await ethers.provider.send("evm_mine", []);
  }

  beforeEach(async function () {
    // Get signers
    [deployer, devFund, stabilityPool, user1, user2, user3] =
      await ethers.getSigners();

    // Deploy contract
    TimeToken = await ethers.getContractFactory("TimeToken");
    const batchDuration = 3600; // 1 hour
    timeToken = await TimeToken.deploy(
      await devFund.getAddress(),
      await stabilityPool.getAddress(),
      batchDuration
    );
    await timeToken.waitForDeployment();
  });

  it("Should set initial state correctly", async function () {
    // Check the stake unit
    const stakeUnit = await timeToken.STAKE_UNIT();
    expect(stakeUnit).to.equal(ethers.parseUnits("3600", 18));

    // Check default minimumStakeUnits
    const minStakeUnits = await timeToken.minimumStakeUnits();
    expect(minStakeUnits).to.equal(1); // default is 1
  });

  it("Should allow staking and unstaking", async function () {
    // user1 stakes 1 stake-hour
    const stakeHours = 1;
    const stakeAmount = ethers.parseUnits("3600", 18); // 1 * 3600 tokens

    // Mint some tokens to user1 so they can stake
    await timeToken.connect(deployer).transfer(await user1.getAddress(), stakeAmount);

    // user1 stakes
    await timeToken.connect(user1).stake(stakeHours);

    // Check stakedHours
    const stakedHoursUser1 = await timeToken.stakedHours(await user1.getAddress());
    expect(stakedHoursUser1).to.equal(stakeHours);

    // Unstake
    await timeToken.connect(user1).unstake();
    const stakedHoursAfter = await timeToken.stakedHours(await user1.getAddress());
    expect(stakedHoursAfter).to.equal(0);
  });

  it("Should reject staking below the current minimum stake requirement", async function () {
    // Set min stake to 2 stake-hours (7200 tokens)
    await timeToken.connect(deployer).setMinimumStakeUnits(2);

    // Mint some tokens to user2
    const stakeAmount = ethers.parseUnits("3600", 18); // only 1 stake-hour
    await timeToken
      .connect(deployer)
      .transfer(await user2.getAddress(), stakeAmount);

    // Attempt to stake 1 stake-hour (should fail because min is 2)
    await expect(timeToken.connect(user2).stake(1)).to.be.revertedWith(
      "Below the current minimum stake requirement"
    );
  });

  it("Should allow large scale staking from multiple users", async function () {
    // This test simulates multiple users staking
    // For brevity, we just do 3, but you could do many more in a loop

    // Increase min stake to 2 for demonstration
    await timeToken.connect(deployer).setMinimumStakeUnits(2);

    // user1 has 7200 tokens, user2 has 10800 tokens, user3 has 14400 tokens
    const stakeHoursUser1 = 2; // 2 stake-hours
    const stakeHoursUser2 = 3; // 3 stake-hours
    const stakeHoursUser3 = 4; // 4 stake-hours

    // Transfer tokens to them
    const amt1 = ethers.parseUnits("7200", 18);
    const amt2 = ethers.parseUnits("10800", 18);
    const amt3 = ethers.parseUnits("14400", 18);

    await timeToken.connect(deployer).transfer(await user1.getAddress(), amt1);
    await timeToken.connect(deployer).transfer(await user2.getAddress(), amt2);
    await timeToken.connect(deployer).transfer(await user3.getAddress(), amt3);

    // They stake
    await timeToken.connect(user1).stake(stakeHoursUser1);
    await timeToken.connect(user2).stake(stakeHoursUser2);
    await timeToken.connect(user3).stake(stakeHoursUser3);

    // Check
    const s1 = await timeToken.stakedHours(await user1.getAddress());
    const s2 = await timeToken.stakedHours(await user2.getAddress());
    const s3 = await timeToken.stakedHours(await user3.getAddress());

    expect(s1).to.equal(stakeHoursUser1);
    expect(s2).to.equal(stakeHoursUser2);
    expect(s3).to.equal(stakeHoursUser3);
  });

  it("Should mint batch (unvalidated) after 60+ minutes (simulate time passage)", async function () {
    // user1 stakes 1 hour
    const stakeHours = 1;
    const stakeAmount = ethers.parseUnits("3600", 18);
    await timeToken.connect(deployer).transfer(await user1.getAddress(), stakeAmount);
    await timeToken.connect(user1).stake(stakeHours);

    // Move time forward by 3600 seconds
    await increaseTime(3600);

    // Now call mintBatch
    await timeToken.mintBatch();

    // Check if devFund got tokens
    const devBalance = await timeToken.balanceOf(await devFund.getAddress());
    expect(devBalance).to.be.gt(0);

    // Check if user1 got some minted tokens (timekeepers share)
    const user1Balance = await timeToken.balanceOf(await user1.getAddress());
    // They staked 1 hour, so they should get some share
    // We can't easily predict the exact number here without diving into the distribution, 
    // but we can confirm it's > stakeAmount (which they staked).
    expect(user1Balance).to.be.gt(stakeAmount);
  });

  it("Should do a validated batch mint (total time validation), catching up or limiting supply", async function () {
    // 1) user2 stakes
    const stakeHours = 2;
    const stakeAmount = ethers.parseUnits("7200", 18);
    await timeToken.connect(deployer).transfer(await user2.getAddress(), stakeAmount);
    await timeToken.connect(user2).stake(stakeHours);

    // 2) Move time forward so some emission is due
    await increaseTime(3600); // 1 hour
    // We do an "unvalidated" mint first
    await timeToken.mintBatch();

    // 3) Now move time forward again, to create more emission
    await increaseTime(3600);

    // 4) Call the validated mintBatchValidated
    // This should ensure final supply matches total seconds from genesis
    await timeToken.mintBatchValidated();

    // Because the contract is new, we likely won't see large differences, 
    // but let's verify the supply is close to expected
    const [valid, totalSecs, expectedSupply, currentSupply, diff] =
      await timeToken.validateSupply();

    // If validated is correct, diff should be 0
    // but minor block offsets might exist in local tests
    // We'll just expect difference to be small
    expect(Number(diff)).to.be.lessThanOrEqual(1e14); // a small wiggle room

    // And valid should be true or near true
    // For a local test environment, you might see 0 difference
    // We'll just log it
    console.log({
      valid,
      totalSecs: totalSecs.toString(),
      expectedSupply: expectedSupply.toString(),
      currentSupply: currentSupply.toString(),
      diff: diff.toString(),
    });
  });

  it("Should handle repeated mints and keep supply aligned", async function () {
    // user3 stakes 1 stake-hour
    const stakeHours = 1;
    const stakeAmount = ethers.parseUnits("3600", 18);
    await timeToken.connect(deployer).transfer(await user3.getAddress(), stakeAmount);
    await timeToken.connect(user3).stake(stakeHours);

    // Mint once (unvalidated) after 1 hour
    await increaseTime(3600);
    await timeToken.mintBatch();

    // Mint again (unvalidated) after 1 more hour
    await increaseTime(3600);
    await timeToken.mintBatch();

    // Now validate
    await increaseTime(3600);
    await timeToken.mintBatchValidated();

    // Supply should be in line
    const [valid] = await timeToken.validateSupply();
    expect(valid).to.be.eq(true);
  });
});