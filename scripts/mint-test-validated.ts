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

async function main() {
    const deployInfo = await loadDeploymentInfo();
    
    const [signer] = await ethers.getSigners();
    console.log("Signer Address:", signer.address);
    console.log("Using contract at:", deployInfo.contractAddress);
    
    const TimeToken = await ethers.getContractFactory("TimeToken");
    const timeToken = await TimeToken.attach(deployInfo.contractAddress);

    // Get initial state
    console.log("\nInitial State:");
    const initialBalance = await timeToken.balanceOf(deployInfo.rewardWallet);
    const initialValidation = await timeToken.validateSupply();
    
    console.log("Initial Balance:", formatUnits(initialBalance, 18), "TTB");
    console.log("Initial Supply Validation:", {
        valid: initialValidation[0],
        totalSeconds: initialValidation[1].toString(),
        expectedSupply: formatUnits(initialValidation[2], 18),
        currentSupply: formatUnits(initialValidation[3], 18),
        difference: formatUnits(initialValidation[4], 18)
    });

    // Random time between 1-100 minutes using timestamp as seed
    const seed = Date.now() % 100;  // Use last 2 digits of timestamp
    const minutesToSimulate = (seed % 100) + 1;
    const secondsToSimulate = minutesToSimulate * 60;
    
    console.log(`\nSimulating time passage (${minutesToSimulate} minutes)...`);
    await ethers.provider.send("evm_increaseTime", [secondsToSimulate]);
    await ethers.provider.send("evm_mine", []);

    // Perform validated mint
    console.log("Calling mintBatchValidated()...");
    const mintTx = await timeToken.mintBatchValidated();
    const receipt = await mintTx.wait();

    // Get final state
    const finalBalance = await timeToken.balanceOf(deployInfo.rewardWallet);
    const finalValidation = await timeToken.validateSupply();
    const tokensEarned = Number(formatUnits(finalBalance - initialBalance, 18));
    
    console.log("\nFinal State:");
    console.log("Final Balance:", formatUnits(finalBalance, 18), "TTB");
    console.log("Tokens Earned:", tokensEarned.toFixed(2), "TTB");
    console.log("Expected Tokens:", secondsToSimulate);
    console.log("Final Supply Validation:", {
        valid: finalValidation[0],
        totalSeconds: finalValidation[1].toString(),
        expectedSupply: formatUnits(finalValidation[2], 18),
        currentSupply: formatUnits(finalValidation[3], 18),
        difference: formatUnits(finalValidation[4], 18)
    });
    
    // Log events
    const mintEvents = receipt.logs.filter(
        log => timeToken.interface.parseLog(log).name === "TokensMinted"
    );
    const validationEvents = receipt.logs.filter(
        log => timeToken.interface.parseLog(log).name === "SupplyValidation"
    );

    console.log("\nEvents Emitted:");
    mintEvents.forEach(log => {
        const parsed = timeToken.interface.parseLog(log);
        console.log("TokensMinted:", {
            amount: formatUnits(parsed.args.amount, 18),
            validated: parsed.args.validated
        });
    });

    validationEvents.forEach(log => {
        const parsed = timeToken.interface.parseLog(log);
        console.log("SupplyValidation:", {
            totalSeconds: parsed.args.totalSecondsSinceGenesis.toString(),
            previousSupply: formatUnits(parsed.args.previousSupply, 18),
            expectedSupply: formatUnits(parsed.args.expectedSupply, 18),
            adjustmentAmount: formatUnits(parsed.args.adjustmentAmount, 18),
            validated: parsed.args.validated
        });
    });
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
