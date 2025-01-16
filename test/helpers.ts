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