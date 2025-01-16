// test/helpers.ts
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from "hardhat";
import { expect } from "chai";

export const STAKE_UNIT = ethers.parseEther("3600");
export const UNSTAKE_DELAY = 3 * 24 * 60 * 60; // 3 days in seconds
export const RENEWAL_PERIOD = 180 * 24 * 60 * 60; // 180 days in seconds

export async function deployContracts() {
  // Deploy TTB Token
  const TTBToken = await ethers.getContractFactory("TimeTickBaseToken");
  const token = await TTBToken.deploy();
  await token.waitForDeployment();

  // Deploy Depot with dev fund as owner for testing
  const [owner] = await ethers.getSigners();
  const TTBDepot = await ethers.getContractFactory("TimeTickBaseDepot");
  const depot = await TTBDepot.deploy(
    await token.getAddress(),
    owner.address // Dev fund address
  );
  await depot.waitForDeployment();

  return { token, depot };
}

export async function setupContracts() {
  const { token, depot } = await deployContracts();
  
  // Enable minting and staking
  await token.toggleMinting();
  await depot.toggleStaking();
  await depot.toggleRewards();

  return { token, depot };
}

// test/TimeTickBaseToken.test.ts
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContracts } from "./helpers";

describe("TimeTickBaseToken", function () {
  describe("Deployment", function () {
    it("Should deploy with correct initial state", async function () {
      const { token } = await loadFixture(deployContracts);
      
      const stats = await token.getTokenStats();
      expect(stats._mintingEnabled).to.be.false;
      expect(stats._currentSupply).to.equal(0);
    });
  });

  describe("Token Generation", function () {
    it("Should mint correct amount of tokens per second", async function () {
      const { token } = await loadFixture(deployContracts);
      
      // Enable minting
      await token.toggleMinting();
      
      // Advance time by 100 seconds
      await time.increase(100);
      
      // Mint tokens
      await token.mintTokens();
      
      // Check supply (should be 100 tokens)
      const supply = await token.totalSupply();
      expect(supply).to.equal(ethers.parseEther("100"));
    });

    it("Should prevent minting if minimum time hasn't passed", async function () {
      const { token } = await loadFixture(deployContracts);
      
      await token.toggleMinting();
      await token.mintTokens();
      
      // Try to mint again immediately
      await expect(token.mintTokens()).to.be.revertedWith("Minimum mint interval not met");
    });
  });
});

// test/TimeTickBaseDepot.test.ts
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { deployContracts, setupContracts, STAKE_UNIT, UNSTAKE_DELAY } from "./helpers";

describe("TimeTickBaseDepot", function () {
  describe("Staking", function () {
    it("Should allow staking whole units", async function () {
      const { token, depot } = await loadFixture(setupContracts);
      const [owner] = await ethers.getSigners();

      // Mint some tokens first
      await time.increase(3600);
      await token.mintTokens();
      
      // Approve depot to spend tokens
      await token.approve(await depot.getAddress(), STAKE_UNIT);
      
      // Stake one unit
      await depot.stake(STAKE_UNIT);
      
      const stakerInfo = await depot.getStakerInfo(owner.address);
      expect(stakerInfo.stakedAmount).to.equal(STAKE_UNIT);
    });

    it("Should reject non-whole unit stakes", async function () {
      const { token, depot } = await loadFixture(setupContracts);
      
      // Try to stake 3599 tokens (less than one unit)
      await expect(
        depot.stake(ethers.parseEther("3599"))
      ).to.be.revertedWith("Must stake whole units");
    });
  });

  describe("Unstaking", function () {
    it("Should enforce unstake delay", async function () {
      const { token, depot } = await loadFixture(setupContracts);
      const [owner] = await ethers.getSigners();

      // Setup: Mint and stake tokens
      await time.increase(3600);
      await token.mintTokens();
      await token.approve(await depot.getAddress(), STAKE_UNIT);
      await depot.stake(STAKE_UNIT);

      // Request unstake
      await depot.requestUnstake();
      
      // Try to unstake immediately (should fail)
      await expect(depot.unstake()).to.be.revertedWith("Not ready");
      
      // Advance time past delay
      await time.increase(UNSTAKE_DELAY);
      
      // Should now succeed
      await depot.unstake();
      
      const stakerInfo = await depot.getStakerInfo(owner.address);
      expect(stakerInfo.stakedAmount).to.equal(0);
    });
  });

  describe("Rewards", function () {
    it("Should distribute rewards correctly", async function () {
      const { token, depot } = await loadFixture(setupContracts);
      const [owner] = await ethers.getSigners();

      // Setup: Mint and stake tokens
      await time.increase(3600);
      await token.mintTokens();
      await token.approve(await depot.getAddress(), STAKE_UNIT);
      await depot.stake(STAKE_UNIT);

      // Generate more tokens
      await time.increase(3600);
      await token.mintTokens();
      
      // Process new mint and rewards
      await depot.processNewMint();
      await depot.processRewardBatch();
      
      // Check unclaimed rewards
      const stakerInfo = await depot.getStakerInfo(owner.address);
      expect(stakerInfo.unclaimedRewards).to.be.gt(0);
    });
  });
});