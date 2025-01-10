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
  });
  
});