import { expect } from "chai";
import { ethers } from "hardhat";
import { TimeTickBase } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("TimeTickBase", function () {
  let ttb: TimeTickBase;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let devFund: SignerWithAddress;

  const isWithinRange = (actual: bigint, expected: bigint, toleranceSeconds = 10n) => {
    const tokenTolerance = ethers.parseEther(toleranceSeconds.toString());
    const lower = expected - tokenTolerance;
    const upper = expected + tokenTolerance;
    return actual >= lower && actual <= upper;
  };

  const getElapsedTime = async (action: () => Promise<void>): Promise<number> => {
    const before = await time.latest();
    await action();
    const after = await time.latest();
    return after - before;
  };

  beforeEach(async function () {
    // Get signers
    [owner, addr1, addr2, devFund] = await ethers.getSigners();

    // Simple deployment pattern that we know works
    const TimeTickBaseFactory = await ethers.getContractFactory("TimeTickBase");
    ttb = await TimeTickBaseFactory.deploy(await devFund.getAddress());
    await ttb.waitForDeployment();

    console.log("Contract deployed to:", await ttb.getAddress());
  });

  describe("Core Functions", function () {
    it("Should stake tokens and track timing accurately", async function () {
      // 1. Advance time by 4 hours to accumulate rewards
      await time.increase(14400); // 4 hours
      console.log("Time advanced by 4 hours");
    
      // 2. Process rewards - should all go to dev fund as there are no stakers
      await ttb.processRewards();
      console.log("Rewards processed");
    
      // 3. Check dev fund balance (should be ~4 hours worth of tokens)
      const expectedDevFundTokens = ethers.parseEther("14400"); // 1 token per second for 4 hours
      const tolerance = ethers.parseEther("10"); // 10 seconds of tokens as tolerance
      
      const devFundBalance = await ttb.balanceOf(devFund.address);
      console.log("Dev fund balance:", devFundBalance.toString());
      
      // Verify balance is within expected range
      expect(devFundBalance).to.be.gt(expectedDevFundTokens.sub(tolerance));
      expect(devFundBalance).to.be.lt(expectedDevFundTokens.add(tolerance));
    
      // 4. Transfer stake amount to test user (addr1)
      const stakeAmount = ethers.parseEther("3600");
      await ttb.connect(devFund).transfer(addr1.address, stakeAmount);
      
      // Verify transfer
      const addr1Balance = await ttb.balanceOf(addr1.address);
      expect(addr1Balance).to.equal(stakeAmount);
      console.log("Tokens transferred to test user");
    
      // 5. Stake tokens
      // First approve
      await ttb.connect(addr1).approve(await ttb.getAddress(), stakeAmount);
      console.log("Spending approved");
      
      // Then stake and measure timing
      const stakeElapsed = await getElapsedTime(async () => {
        await ttb.connect(addr1).stake(stakeAmount);
      });
      console.log("Stake completed in", stakeElapsed, "seconds");
    
      // Verify stake
      const stakerInfo = await ttb.getStakerInfo(addr1.address);
      expect(stakerInfo[0]).to.equal(stakeAmount); // Staked amount
      expect(stakerInfo[1]).to.equal(0n);          // Unclaimed rewards
      expect(stakerInfo[3]).to.equal(0n);          // No unstake time
    
      // Check network stats
      const networkStats = await ttb.getNetworkStats();
      expect(networkStats[0]).to.equal(stakeAmount); // Total staked
      expect(networkStats[1]).to.equal(1n);          // One staker
    });

    it("Should track rewards with execution timing", async function () {
      // Setup stake
      await time.increase(7200);
      await ttb.processRewards();
      const stakeAmount = ethers.parseEther("3600");
      await ttb.connect(devFund).transfer(addr1.address, stakeAmount);
      await ttb.connect(addr1).approve(ttb.address, stakeAmount);

      const stakeElapsed = await getElapsedTime(async () => {
        await ttb.connect(addr1).stake(stakeAmount);
      });

      // Move forward and process rewards
      await time.increase(3600);

      const rewardElapsed = await getElapsedTime(async () => {
        await ttb.processRewards();
      });

      // Calculate expected rewards including all delays
      const totalElapsed = 3600n + BigInt(stakeElapsed) + BigInt(rewardElapsed);
      const expectedRewards = ethers.parseEther((Number(totalElapsed) * 0.7).toString());

      const stakerInfo = await ttb.getStakerInfo(addr1.address);
      expect(isWithinRange(stakerInfo[1], expectedRewards)).to.be.true;
    });

    it("Should handle unstaking with timing considerations", async function () {
      // Setup stake
      await time.increase(7200);
      await ttb.processRewards();
      const stakeAmount = ethers.parseEther("3600");
      await ttb.connect(devFund).transfer(addr1.address, stakeAmount);
      await ttb.connect(addr1).approve(ttb.address, stakeAmount);
      await ttb.connect(addr1).stake(stakeAmount);

      // Request unstake
      const unstakeRequestElapsed = await getElapsedTime(async () => {
        await ttb.connect(addr1).requestUnstake(stakeAmount);
      });

      // Verify unstake request state
      let stakerInfo = await ttb.getStakerInfo(addr1.address);
      expect(stakerInfo[3]).to.be.gt(0n);

      // Move past delay and complete unstake
      // 3 days + execution time + buffer
      await time.increase(86400 * 3 + unstakeRequestElapsed + 10);

      const unstakeElapsed = await getElapsedTime(async () => {
        await ttb.connect(addr1).unstake();
      });

      // Final state verification
      stakerInfo = await ttb.getStakerInfo(addr1.address);
      expect(stakerInfo[0]).to.equal(0n);
      expect(stakerInfo[3]).to.equal(0n);

      const networkStats = await ttb.getNetworkStats();
      expect(networkStats[0]).to.equal(0n);
      expect(networkStats[1]).to.equal(0n);
    });
  });

  describe("View Functions", function () {
    it("Should track network stats with timing accuracy", async function () {
      // Initial state
      let stats = await ttb.getNetworkStats();
      expect(stats[0]).to.equal(0n);
      expect(stats[1]).to.equal(0n);
      expect(stats[2]).to.equal(ethers.parseEther("1"));
      expect(stats[3]).to.equal(ethers.parseEther("3600"));

      // Setup staking
      await time.increase(7200);
      await ttb.processRewards();
      const stakeAmount = ethers.parseEther("3600");

      // First staker
      await ttb.connect(devFund).transfer(addr1.address, stakeAmount);
      await ttb.connect(addr1).approve(ttb.address, stakeAmount);
      const firstStakeElapsed = await getElapsedTime(async () => {
        await ttb.connect(addr1).stake(stakeAmount);
      });

      stats = await ttb.getNetworkStats();
      expect(stats[0]).to.equal(stakeAmount);
      expect(stats[1]).to.equal(1n);

      // Second staker
      await ttb.connect(devFund).transfer(addr2.address, stakeAmount);
      await ttb.connect(addr2).approve(ttb.address, stakeAmount);
      const secondStakeElapsed = await getElapsedTime(async () => {
        await ttb.connect(addr2).stake(stakeAmount);
      });

      stats = await ttb.getNetworkStats();
      expect(stats[0]).to.equal(stakeAmount * 2n);
      expect(stats[1]).to.equal(2n);
    });
  });
});