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
      
      // Transfer tokens to addr1
      const addr1Address = await addr1.getAddress();
      await ttb.connect(devFund).transfer(addr1Address, stakeAmount);
      
      // Create a single contract instance for addr1 and use it consistently
      const addr1Contract = ttb.connect(addr1);
      
      // Approve using addr1's instance
      await addr1Contract.approve(await ttb.getAddress(), stakeAmount);
      
      // Log everything before stake
      console.log("\nFinal check before stake:");
      console.log("Addr1 balance:", (await ttb.balanceOf(addr1Address)).toString());
      console.log("Allowance:", (await ttb.allowance(addr1Address, await ttb.getAddress())).toString());
      console.log("Staking with address:", await addr1Contract.signer.getAddress());
      
      // Stake using the same addr1 instance
      await addr1Contract.stake(stakeAmount);
  });
  });
});