import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
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