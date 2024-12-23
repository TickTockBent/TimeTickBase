import { ethers } from "hardhat";
import { formatUnits } from "ethers";
import * as fs from "fs";

async function main() {
  console.log("Starting deployment...");

  const [deployer, devFund, stabilityPool] = await ethers.getSigners();
  
  console.log("Deployer address:", deployer.address);
  console.log("Dev Fund address:", devFund.address);
  console.log("Stability Pool address:", stabilityPool.address);

  const TimeToken = await ethers.getContractFactory("TimeToken");
  const batchDuration = 3600; // 1 hour in seconds
  
  const timeToken = await TimeToken.deploy(
    devFund.address,
    stabilityPool.address,
    batchDuration
  );

  await timeToken.waitForDeployment();
  const contractAddress = await timeToken.getAddress();

  console.log("TimeToken deployed to:", contractAddress);

  // Verify staking constants
  console.log("\nVerifying staking constants...");
  const stakeUnit = await timeToken.STAKE_UNIT();
  console.log("Stake unit:", formatUnits(stakeUnit, 18), "TTB");

  // Save deployment information
  const network = await ethers.provider.getNetwork();
  
  const deploymentInfo = {
    contractAddress: contractAddress,
    devFundAddress: devFund.address,
    stabilityPoolAddress: stabilityPool.address,
    deployerAddress: deployer.address,
    batchDuration: batchDuration,
    stakeUnit: formatUnits(stakeUnit, 18),
    deploymentTime: new Date().toISOString(),
    networkName: network.name || "unknown",
    chainId: Number(network.chainId)
  };

  const deploymentFile = 'deployment-info.json';
  fs.writeFileSync(
    deploymentFile,
    JSON.stringify(deploymentInfo, null, 2)
  );

  console.log(`Deployment information saved to ${deploymentFile}`);
  console.log("\nDeployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
