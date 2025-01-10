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
      console.log("Starting stake test...");
      
      // Log initial addresses
      console.log("Dev Fund:", await devFund.getAddress());
      console.log("Addr1:", await addr1.getAddress());
      console.log("Contract:", await ttb.getAddress());
      
      // Process initial rewards
      await time.increase(7200);
      console.log("Time increased");
      
      const rewardElapsed = await getElapsedTime(async () => {
        await ttb.processRewards();
      });
      console.log("Rewards processed");
      
      // Setup stake amount
      const stakeAmount = ethers.parseEther("3600");
      console.log("Transferring", stakeAmount.toString(), "tokens to addr1");
      
      // Transfer tokens to addr1
      const devFundContract = ttb.connect(devFund);
      await devFundContract.transfer(await addr1.getAddress(), stakeAmount);
      console.log("Tokens transferred");
      
      // Check initial state
      let stakerInfo = await ttb.getStakerInfo(await addr1.getAddress());
      console.log("Initial staker info:", stakerInfo);
      expect(stakerInfo[0]).to.equal(0n);
      
      // Approve and stake
      const addr1Contract = ttb.connect(addr1);
      await addr1Contract.approve(await ttb.getAddress(), stakeAmount);
      console.log("Tokens approved");
      
      const stakeElapsed = await getElapsedTime(async () => {
        await addr1Contract.stake(stakeAmount);
      });
      console.log("Stake completed");
      
      // Verify final state
      stakerInfo = await ttb.getStakerInfo(await addr1.getAddress());
      console.log("Final staker info:", stakerInfo);
      
      expect(stakerInfo[0]).to.equal(stakeAmount);
      expect(stakerInfo[1]).to.equal(0n);
      expect(stakerInfo[3]).to.equal(0n);
      
      const networkStats = await ttb.getNetworkStats();
      expect(networkStats[0]).to.equal(stakeAmount);
      expect(networkStats[1]).to.equal(1n);
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