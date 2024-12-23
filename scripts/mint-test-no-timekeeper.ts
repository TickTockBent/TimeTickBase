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

    console.log("\nUsing addresses:");
    console.log("Dev Fund:", devFund.address);
    console.log("Stability Pool:", stabilityPool.address);
    console.log("Contract:", deployInfo.contractAddress);

    const TimeToken = await ethers.getContractFactory("TimeToken");
    const timeToken = await TimeToken.attach(deployInfo.contractAddress);

    // Get initial state
    console.log("\nInitial State:");
    const initialDevBalance = await timeToken.balanceOf(devFund.address);
    const initialStabilityBalance = await timeToken.balanceOf(stabilityPool.address);
    
    console.log("Dev Fund Balance:", formatUnits(initialDevBalance, 18), "TTB");
    console.log("Stability Pool Balance:", formatUnits(initialStabilityBalance, 18), "TTB");

    // Simulate time (60 minutes plus buffer)
    const minutesToSimulate = 65;
    const secondsToSimulate = minutesToSimulate * 60;
    
    console.log(`\nSimulating time passage (${minutesToSimulate} minutes)...`);
    await ethers.provider.send("evm_increaseTime", [secondsToSimulate]);
    await ethers.provider.send("evm_mine", []);

    // Call validated mint
    console.log("Calling mintBatch()...");
    const mintTx = await timeToken.mintBatch();
    const receipt = await mintTx.wait();

    // Get final state and changes
    const finalDevBalance = await timeToken.balanceOf(devFund.address);
    const finalStabilityBalance = await timeToken.balanceOf(stabilityPool.address);
    
    const devChange = Number(formatUnits(finalDevBalance - initialDevBalance, 18));
    const stabilityChange = Number(formatUnits(finalStabilityBalance - initialStabilityBalance, 18));
    
    console.log("\nFinal State:");
    console.log("Dev Fund Balance:", formatUnits(finalDevBalance, 18), "TTB");
    console.log("Stability Pool Balance:", formatUnits(finalStabilityBalance, 18), "TTB");
    
    console.log("\nChanges:");
    console.log("Dev Fund Change:", devChange.toFixed(2), "TTB");
    console.log("Stability Pool Change:", stabilityChange.toFixed(2), "TTB");

    // Verify distribution percentages
    const totalMinted = devChange + stabilityChange;
    const devPercentage = (devChange / totalMinted) * 100;
    const stabilityPercentage = (stabilityChange / totalMinted) * 100;

    console.log("\nDistribution Percentages:");
    console.log("Dev Fund:", devPercentage.toFixed(1), "% (expected 70%)");
    console.log("Stability Pool:", stabilityPercentage.toFixed(1), "% (expected 30%)");

    // Log events
    console.log("\nEvents Emitted:");
    const fundDistEvents = receipt.logs.filter(
        log => {
            try {
                return timeToken.interface.parseLog(log).name === "FundDistribution";
            } catch {
                return false;
            }
        }
    );

    fundDistEvents.forEach(log => {
        const parsed = timeToken.interface.parseLog(log);
        console.log("FundDistribution:", {
            devAmount: formatUnits(parsed.args.devAmount, 18),
            stabilityAmount: formatUnits(parsed.args.stabilityAmount, 18),
            timekeepersAmount: formatUnits(parsed.args.timekeepersAmount, 18),
            validTimekeepers: Number(parsed.args.validTimekeepers),
            timestamp: new Date(Number(parsed.args.timestamp) * 1000).toISOString()
        });
    });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
