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

  const isWithinRange = (actual: bigint, expected: bigint, toleranceSeconds = 30n) => {
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
    [owner, devFund, addr1, addr2] = await ethers.getSigners();

    // Simple deployment pattern that we know works
    const TimeTickBaseFactory = await ethers.getContractFactory("TimeTickBase");
    ttb = await TimeTickBaseFactory.deploy(await devFund.getAddress());
    await ttb.waitForDeployment();

    console.log("Contract deployed to:", await ttb.getAddress());
  });

  describe("Core Functions", function () {
    it("Should stake tokens and track timing accurately", async function () {
      // Initial reward processing
      await time.increase(14400);
      await ttb.processRewards();
    
      const stakeAmount = ethers.parseEther("3600");
      const contractAddress = await ttb.getAddress();
      const addr1Address = await addr1.getAddress();
      
      // Transfer tokens to addr1
      await ttb.connect(devFund).transfer(addr1Address, stakeAmount);
      
      // Create a single contract instance for addr1 and use it consistently
      const addr1Contract = ttb.connect(addr1);
      
      // Approve using addr1's instance
      await addr1Contract.approve(contractAddress, stakeAmount);
      
      // Log everything before stake
      console.log("\nFinal check before stake:");
      console.log("Contract address:", contractAddress);
      console.log("Addr1 address:", addr1Address);
      console.log("Addr1 balance:", (await ttb.balanceOf(addr1Address)).toString());
      console.log("Allowance:", (await ttb.allowance(addr1Address, contractAddress)).toString());
      console.log("Connected address:", await addr1.getAddress());  // Changed this line
      
      // Stake using the same addr1 instance
      await addr1Contract.stake(stakeAmount);
    });
    it("Should distribute rewards correctly via processRewards", async function () {
      // Initial stake setup
      await time.increase(14400); // 4 hours for initial tokens
      await ttb.processRewards();
  
      const stakeAmount = ethers.parseEther("3600");
      const addr1Contract = ttb.connect(addr1);
      
      // Transfer and stake
      await ttb.connect(devFund).transfer(addr1.getAddress(), stakeAmount);
      await addr1Contract.stake(stakeAmount);
  
      // Advance time and process rewards
      await time.increase(3600); // 1 hour
      const expectedBase = ethers.parseEther("2520"); // Base expectation: 3600 * 0.7
      
      // Process rewards and check elapsed time
      const before = await time.latest();
      await ttb.processRewards();
      const after = await time.latest();
      
      console.log("Process rewards took:", after - before, "seconds");
      
      // Get actual rewards
      const stakerInfo = await ttb.getStakerInfo(addr1.getAddress());
      console.log("Expected base rewards:", expectedBase.toString());
      console.log("Actual rewards:", stakerInfo[1].toString());
      
      // Check with tolerance
      expect(isWithinRange(stakerInfo[1], expectedBase, 10n)).to.be.true; // Allow 10 seconds of variance
    });
    it("Should handle time validation correctly", async function() {
      await time.increase(14400);
      await ttb.processRewards();
      
      const stakeAmount = ethers.parseEther("3600");
      await ttb.connect(devFund).transfer(addr1.address, stakeAmount);
      await ttb.connect(addr1).stake(stakeAmount);
      
      await time.increase(3600);
      
      console.log("\nPre-validation state:");
      console.log("Last mint time:", Number(await ttb.lastMintTime()));
      console.log("Current time:", await time.latest());
      console.log("Expected tokens to mint:", (await time.latest()) - Number(await ttb.lastMintTime()));

      const before = await time.latest();
      const tx = await ttb.validateTotalTime();
      const receipt = await tx.wait();
      console.log("\nTransaction events:");
      const rewardsEvent = receipt.events?.find(e => e.event === 'RewardsProcessed');
      console.log("Rewards event:", rewardsEvent ? {
          totalRewards: rewardsEvent.args?.totalRewards.toString(),
          devShare: rewardsEvent.args?.devShare.toString(),
          stakerShare: rewardsEvent.args?.stakerShare.toString(),
          correctionFactor: rewardsEvent.args?.correctionFactor.toString()
      } : "No rewards event found");
      const correction = receipt.events?.find(e => e.event === 'TimeValidation')?.args?.correctionFactor;
      const after = await time.latest();
      

      console.log("\nValidation details:");
      console.log("Execution time:", after - before, "seconds");
      console.log("Raw correction:", correction);
      console.log("Correction toString:", correction?.toString());
      console.log("Correction type:", typeof correction);
      if (typeof correction === 'object') {
          console.log("Correction properties:", Object.keys(correction));
          // If it's a BigNumber-like object, it might have a toString method
          if ('toString' in correction) {
              console.log("Correction toString:", correction.toString());
          }
      }
      
      const stakerInfo = await ttb.getStakerInfo(addr1.address);
      const expectedBase = ethers.parseEther("2520");
      
      console.log("Expected rewards:", expectedBase.toString());
      console.log("Actual rewards:", stakerInfo.unclaimedRewards.toString());
      console.log("Difference:", (stakerInfo.unclaimedRewards - expectedBase).toString());
      
      expect(isWithinRange(stakerInfo.unclaimedRewards, expectedBase, 30n)).to.be.true;
    });
    it("Should handle unstaking process correctly", async function() {
      // Initial setup
      await time.increase(14400);
      await ttb.processRewards();
      
      const stakeAmount = ethers.parseEther("3600");
      const addr1Contract = ttb.connect(addr1);
      
      // Get initial balance for later comparison
      const initialBalance = await ttb.balanceOf(addr1.getAddress());
      
      // Setup stake
      await ttb.connect(devFund).transfer(addr1.getAddress(), stakeAmount);
      await addr1Contract.stake(stakeAmount);
      
      // Request unstake
      await addr1Contract.requestUnstake(stakeAmount);
      
      // Verify unstake request
      let stakerInfo = await ttb.getStakerInfo(addr1.getAddress());
      expect(stakerInfo[3]).to.be.gt(0n); // Unstake time should be set
      
      // Advance time past unstake delay (3 days)
      await time.increase(3 * 24 * 3600 + 10); // 3 days + buffer
      
      // Complete unstake
      await addr1Contract.unstake();
      
      // Verify unstake completed
      stakerInfo = await ttb.getStakerInfo(addr1.getAddress());
      expect(stakerInfo[0]).to.equal(0n); // Stake amount should be 0
      expect(stakerInfo[3]).to.equal(0n); // Unstake time should be cleared
      
      // Verify tokens returned
      const finalBalance = await ttb.balanceOf(addr1.getAddress());
      expect(finalBalance).to.be.gte(initialBalance + stakeAmount); // Should have at least initial + stake back
    });
  });
  describe("Advanced Functions", function () {
    it("Should prevent staking non-unit amounts", async function () {
        await time.increase(14400);
        await ttb.processRewards();
        
        const nonUnitAmount = ethers.parseEther("3601"); // Not a multiple of STAKE_UNIT
        await ttb.connect(devFund).transfer(addr1.getAddress(), nonUnitAmount);
        
        await expect(ttb.connect(addr1).stake(nonUnitAmount))
            .to.be.revertedWith("Must stake whole units");
    });

    it("Should handle multiple stakers with correct reward distribution", async function () {
        await time.increase(14400);
        await ttb.processRewards();
        
        const stakeAmount = ethers.parseEther("3600");
        // Setup two stakers with different amounts
        await ttb.connect(devFund).transfer(addr1.getAddress(), stakeAmount * 2n);
        await ttb.connect(devFund).transfer(addr2.getAddress(), stakeAmount);
        
        await ttb.connect(addr1).stake(stakeAmount * 2n);
        await ttb.connect(addr2).stake(stakeAmount);
        
        await time.increase(3600);
        await ttb.processRewards();
        
        const addr1Info = await ttb.getStakerInfo(addr1.getAddress());
        const addr2Info = await ttb.getStakerInfo(addr2.getAddress());
        
        // addr1 should have 2/3 of rewards, addr2 1/3
        expect(addr1Info.unclaimedRewards).to.be.approximately(addr2Info.unclaimedRewards * 2n, ethers.parseEther("1"));
    });

    it("Should handle stake renewal correctly", async function () {
        await time.increase(14400);
        await ttb.processRewards();
        
        const stakeAmount = ethers.parseEther("3600");
        await ttb.connect(devFund).transfer(addr1.getAddress(), stakeAmount);
        await ttb.connect(addr1).stake(stakeAmount);
        
        await time.increase(179 * 24 * 3600); // Just before renewal period
        await ttb.connect(addr1).renewStake();
        
        const stakerInfo = await ttb.getStakerInfo(addr1.getAddress());
        expect(stakerInfo.lastRenewalTime).to.be.approximately(BigInt(await time.latest()), 10n);
    });
    it("Should automatically process expired stakes", async function () {
      await time.increase(14400);
      await ttb.processRewards();
      
      const stakeAmount = ethers.parseEther("3600");
      await ttb.connect(devFund).transfer(addr1.getAddress(), stakeAmount);
      await ttb.connect(addr1).stake(stakeAmount);
      
      // Move past renewal period (180 days + 1 day for safety)
      await time.increase(181 * 24 * 3600);
      
      // Process rewards should trigger expired stake processing
      await ttb.processRewards();
      
      const stakerInfo = await ttb.getStakerInfo(addr1.getAddress());
      expect(stakerInfo.stakedAmount).to.equal(0n);
      
      // Check balance returned (stake + rewards)
      const balance = await ttb.balanceOf(addr1.getAddress());
      expect(balance).to.be.gt(stakeAmount);
  });
  
  it("Should handle unstake cancellation correctly", async function () {
      await time.increase(14400);
      await ttb.processRewards();
      
      const stakeAmount = ethers.parseEther("3600");
      await ttb.connect(devFund).transfer(addr1.getAddress(), stakeAmount);
      await ttb.connect(addr1).stake(stakeAmount);
      
      await ttb.connect(addr1).requestUnstake(stakeAmount);
      await ttb.connect(addr1).cancelUnstake();
      
      const stakerInfo = await ttb.getStakerInfo(addr1.getAddress());
      expect(stakerInfo.unstakeTime).to.equal(0n);
      expect(stakerInfo.stakedAmount).to.equal(stakeAmount);
  });
  
  it("Should handle reward claiming correctly", async function () {
      await time.increase(14400);
      await ttb.processRewards();
      
      const stakeAmount = ethers.parseEther("3600");
      await ttb.connect(devFund).transfer(addr1.getAddress(), stakeAmount);
      await ttb.connect(addr1).stake(stakeAmount);
      
      // Generate some rewards
      await time.increase(3600);
      await ttb.processRewards();
      
      const beforeBalance = await ttb.balanceOf(addr1.getAddress());
      const stakerInfo = await ttb.getStakerInfo(addr1.getAddress());
      const rewards = stakerInfo.unclaimedRewards;
      
      await ttb.connect(addr1).claimRewards();
      
      const afterBalance = await ttb.balanceOf(addr1.getAddress());
      expect(afterBalance - beforeBalance).to.equal(rewards);
      
      // Check rewards cleared
      const finalInfo = await ttb.getStakerInfo(addr1.getAddress());
      expect(finalInfo.unclaimedRewards).to.equal(0n);
    });
  });
});