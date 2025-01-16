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