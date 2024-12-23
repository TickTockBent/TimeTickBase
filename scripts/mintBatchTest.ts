import { ethers } from "hardhat";
import { formatUnits } from "ethers";
import * as fs from "fs";

async function loadDeploymentInfo() {
    try {
        const data = fs.readFileSync('deployment-info.json', 'utf8');
        return JSON.parse(data);
    } catch (error) {
        console.error("Could not load deployment info. Have you deployed the contract?");
        throw error;
    }
}

async function simulateAndMint(timeToken: any, rewardWallet: string, timeJumpSeconds: number) {
    // Get initial state
    console.log("\nInitial State:");
    const initialBalance = await timeToken.balanceOf(rewardWallet);
    console.log("Initial Balance:", formatUnits(initialBalance, 18), "TTB");
    const lastMintTime = await timeToken.lastMintTime();
    console.log("Last Mint Time:", new Date(Number(lastMintTime) * 1000).toLocaleString());
    
    // Simulate time passage
    console.log(`\nSimulating time passage (${timeJumpSeconds} seconds)...`);
    await ethers.provider.send("evm_increaseTime", [timeJumpSeconds]);
    await ethers.provider.send("evm_mine", []);

    // Get block time after jump
    const blockAfterJump = await ethers.provider.getBlock('latest');
    console.log("New Block Time:", new Date(Number(blockAfterJump?.timestamp) * 1000).toLocaleString());

    console.log("Calling mintBatch...");
    const mintTx = await timeToken.mintBatch();
    await mintTx.wait();

    // Final state
    console.log("\nFinal State:");
    const finalBalance = await timeToken.balanceOf(rewardWallet);
    console.log("Final Balance:", formatUnits(finalBalance, 18), "TTB");
    
    const earned = finalBalance - initialBalance;
    console.log("Tokens Earned:", formatUnits(earned, 18), "TTB");
    
    // Calculate and show rate
    const actualRate = Number(formatUnits(earned, 18)) / timeJumpSeconds;
    console.log("Actual Token Generation Rate:", actualRate.toFixed(2), "tokens per second");
}

async function main() {
    const deployInfo = await loadDeploymentInfo();
    
    const [signer] = await ethers.getSigners();
    console.log("Signer Address:", signer.address);
    console.log("Using contract at:", deployInfo.contractAddress);
    
    const TimeToken = await ethers.getContractFactory("TimeToken");
    const timeToken = await TimeToken.attach(deployInfo.contractAddress);

    // Default to 1 hour simulation
    const timeJumpSeconds = 3600; // 1 hour
    await simulateAndMint(timeToken, deployInfo.rewardWallet, timeJumpSeconds);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
