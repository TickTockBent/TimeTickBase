import { ethers } from "hardhat";
import { formatUnits } from "ethers";
import * as fs from "fs";

async function loadDeploymentInfo() {
    const data = fs.readFileSync('deployment-info.json', 'utf8');
    return JSON.parse(data);
}

async function main() {
    const deployInfo = await loadDeploymentInfo();
    const [deployer, devFund, stabilityPool] = await ethers.getSigners();
    const TimeToken = await ethers.getContractFactory("TimeToken");
    const timeToken = await TimeToken.attach(deployInfo.contractAddress);

    console.log("\nInitial Balances:");
    console.log("Dev Fund:", formatUnits(await timeToken.balanceOf(devFund.address), 18), "TTB");
    console.log("Stability Pool:", formatUnits(await timeToken.balanceOf(stabilityPool.address), 18), "TTB");
    console.log("Total Supply:", formatUnits(await timeToken.totalSupply(), 18), "TTB");
    
    // Simulate 1 year passing
    const daysToSimulate = 365;
    const secondsToSimulate = daysToSimulate * 24 * 60 * 60;
    
    console.log(`\nSimulating catastrophic ${daysToSimulate} day delay...`);
    await ethers.provider.send("evm_increaseTime", [secondsToSimulate]);
    await ethers.provider.send("evm_mine", []);

    console.log("Attempting recovery mint...");
    await timeToken.mintBatch();
    
    console.log("\nFinal Balances:");
    console.log("Dev Fund:", formatUnits(await timeToken.balanceOf(devFund.address), 18), "TTB");
    console.log("Stability Pool:", formatUnits(await timeToken.balanceOf(stabilityPool.address), 18), "TTB");
    console.log("Total Supply:", formatUnits(await timeToken.totalSupply(), 18), "TTB");

    // Calculate how many tokens were minted
    const tokensPerDay = 86400;
    const expectedTokens = tokensPerDay * daysToSimulate;
    console.log("\nExpected tokens generated:", expectedTokens.toLocaleString(), "TTB");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
