import { ethers } from "hardhat";
import { formatUnits } from "ethers";
import * as fs from "fs";

async function loadDeploymentInfo() {
    const data = fs.readFileSync('deployment-info.json', 'utf8');
    return JSON.parse(data);
}

async function main() {
    const deployInfo = await loadDeploymentInfo();
    const [deployer] = await ethers.getSigners();
    const TimeToken = await ethers.getContractFactory("TimeToken");
    const timeToken = await TimeToken.attach(deployInfo.contractAddress);

    console.log("Initial supply:", formatUnits(await timeToken.totalSupply(), 18), "TTB");
    
    // Simulate 2 days passing
    const daysToSimulate = 2;
    const secondsToSimulate = daysToSimulate * 24 * 60 * 60;
    
    console.log(`\nSimulating ${daysToSimulate} days...`);
    await ethers.provider.send("evm_increaseTime", [secondsToSimulate]);
    await ethers.provider.send("evm_mine", []);

    await timeToken.mintBatch();
    
    console.log("Final supply:", formatUnits(await timeToken.totalSupply(), 18), "TTB");
    console.log("Deployer balance:", formatUnits(await timeToken.balanceOf(deployer.address), 18), "TTB");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
