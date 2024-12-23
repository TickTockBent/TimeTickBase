import { ethers } from "hardhat";
import { formatUnits } from "ethers";
import * as fs from "fs";

async function loadDeploymentInfo() {
    const data = fs.readFileSync('deployment-info.json', 'utf8');
    return JSON.parse(data);
}

async function main() {
    const deployInfo = await loadDeploymentInfo();
    const [deployer, devFund, stabilityPool, keeper1, keeper2, keeper3] = await ethers.getSigners();

    console.log("\nUsing addresses:");
    console.log("Dev Fund:", devFund.address);
    console.log("Stability Pool:", stabilityPool.address);
    console.log("Test Keepers:", keeper1.address, keeper2.address, keeper3.address);
    console.log("Contract:", deployInfo.contractAddress);

    const TimeToken = await ethers.getContractFactory("TimeToken");
    const timeToken = await TimeToken.attach(deployInfo.contractAddress);

    // Setup timekeepers with 1 day stake each if not already staked
    console.log("\nSetting up timekeepers...");
    const transferAmount = ethers.parseEther("86400");
    for (const keeper of [keeper1, keeper2, keeper3]) {
        const stakedDays = await timeToken.stakedDays(keeper.address);
        if (stakedDays.toString() === "0") {
            const devFundToken = timeToken.connect(devFund);
            await devFundToken.transfer(keeper.address, transferAmount);
            const keeperToken = timeToken.connect(keeper);
            await keeperToken.stake(1);
            console.log(`Keeper ${keeper.address} staked 1 day`);
        } else {
            console.log(`Keeper ${keeper.address} already has ${stakedDays.toString()} days staked`);
        }
    }

    // Get initial state
    console.log("\nInitial State:");
    const getBalances = async () => ({
        dev: await timeToken.balanceOf(devFund.address),
        stability: await timeToken.balanceOf(stabilityPool.address),
        keeper1: await timeToken.balanceOf(keeper1.address),
        keeper2: await timeToken.balanceOf(keeper2.address),
        keeper3: await timeToken.balanceOf(keeper3.address)
    });

    const initialBalances = await getBalances();
    Object.entries(initialBalances).forEach(([key, value]) => {
        console.log(`${key} Balance:`, formatUnits(value, 18), "TTB");
    });

    // Simulate time (60 minutes plus buffer)
    const minutesToSimulate = 65;
    const secondsToSimulate = minutesToSimulate * 60;
    
    console.log(`\nSimulating time passage (${minutesToSimulate} minutes)...`);
    await ethers.provider.send("evm_increaseTime", [secondsToSimulate]);
    await ethers.provider.send("evm_mine", []);

    // Call mint
    console.log("Calling mintBatch()...");
    const mintTx = await timeToken.mintBatch();
    const receipt = await mintTx.wait();

    // Get final state and calculate changes
    const finalBalances = await getBalances();
    
    console.log("\nFinal State and Changes:");
    Object.entries(finalBalances).forEach(([key, value]) => {
        const change = Number(formatUnits(value - initialBalances[key], 18));
        console.log(`${key}:`, formatUnits(value, 18), "TTB (Change:", change.toFixed(2), "TTB)");
    });

    // Calculate distribution percentages
    const changes = Object.entries(finalBalances).map(([key, value]) => ({
        key,
        change: Number(formatUnits(value - initialBalances[key], 18))
    }));

    const totalMinted = changes.reduce((acc, curr) => acc + curr.change, 0);

    console.log("\nDistribution Percentages:");
    changes.forEach(({key, change}) => {
        const percentage = (change / totalMinted) * 100;
        console.log(`${key}:`, percentage.toFixed(1), "%");
    });

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
