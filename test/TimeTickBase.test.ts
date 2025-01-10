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
    [owner, devFund, addr1, addr2] = await ethers.getSigners();

    // Simple deployment pattern that we know works
    const TimeTickBaseFactory = await ethers.getContractFactory("TimeTickBase");
    ttb = await TimeTickBaseFactory.deploy(await devFund.getAddress());
    await ttb.waitForDeployment();

    console.log("Contract deployed to:", await ttb.getAddress());
  });

  describe("Core Functions", function () {
    it("Should stake tokens and track timing accurately", async function () {
      // 1. Time and rewards
      await time.increase(14400);
      await ttb.processRewards();
      
      // Log initial balances
      const contractAddress = await ttb.getAddress();
      console.log("Initial balances:");
      console.log("Dev Fund:", (await ttb.balanceOf(devFund.address)).toString());
      console.log("Addr1:", (await ttb.balanceOf(addr1.address)).toString());
      console.log("Contract:", (await ttb.balanceOf(contractAddress)).toString());
    
      // 2. Transfer to addr1
      const stakeAmount = ethers.parseEther("3600");
      await ttb.connect(devFund).transfer(addr1.address, stakeAmount);
      
      // Log post-transfer balances
      console.log("\nPost-transfer balances:");
      console.log("Dev Fund:", (await ttb.balanceOf(devFund.address)).toString());
      console.log("Addr1:", (await ttb.balanceOf(addr1.address)).toString());
      console.log("Contract:", (await ttb.balanceOf(contractAddress)).toString());
    
      // 3. Approval
      await ttb.connect(addr1).approve(contractAddress, stakeAmount);
      
      // Log allowance
      const allowance = await ttb.allowance(addr1.address, contractAddress);
      console.log("\nContract allowance from addr1:", allowance.toString());
    
      // 4. Stake
      const stakeElapsed = await getElapsedTime(async () => {
        await ttb.connect(addr1).stake(stakeAmount);
      });
      
      // Log final balances
      console.log("\nFinal balances:");
      console.log("Dev Fund:", (await ttb.balanceOf(devFund.address)).toString());
      console.log("Addr1:", (await ttb.balanceOf(addr1.address)).toString());
      console.log("Contract:", (await ttb.balanceOf(contractAddress)).toString());
    });
  });
});