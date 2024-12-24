import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

async function increaseTime(seconds: number) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

describe("TimeToken distribution model", function () {
  let TimeToken: any;
  let timeToken: Contract;
  let deployer: Signer;
  let devFund: Signer;
  let user1: Signer;
  let user2: Signer;

  const BATCH_DURATION = 3600; // 1 hour in seconds
  const ONE_HOUR_SECONDS = 3600;
  const STAKE_UNIT = ethers.parseUnits("3600", 18); // One stake hour

  beforeEach(async function () {
    [deployer, devFund, user1, user2] = await ethers.getSigners();

    TimeToken = await ethers.getContractFactory("TimeToken");
    timeToken = await TimeToken.deploy(
      await devFund.getAddress(),
      BATCH_DURATION
    );
    await timeToken.waitForDeployment();
  });

  it("Scenario 1: No stakers at first -> Dev receives 100% of tokens", async () => {
    await expect(timeToken.mintBatch()).to.be.revertedWith(
      "Batch period not reached"
    );

    const timeIncrease = ONE_HOUR_SECONDS * 2;
    await increaseTime(timeIncrease);
    await timeToken.mintBatch();

    const devBalance = await timeToken.balanceOf(await devFund.getAddress());
    const totalTokens = ethers.toBigInt(timeIncrease) * ethers.parseUnits("1", 18);
    expect(devBalance).to.be.closeTo(totalTokens, ethers.parseUnits("2", 18));

    const lastMintTime = await timeToken.lastMintTime();
    const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
    expect(Math.abs(Number(lastMintTime) - blockTimestamp)).to.be.lt(5);
  });

  it("Scenario 2: Dev transfers tokens to users so they can stake", async () => {
    await increaseTime(ONE_HOUR_SECONDS * 2);
    await timeToken.mintBatch();

    const devBalBefore = await timeToken.balanceOf(await devFund.getAddress());
    expect(devBalBefore).to.be.gt(0);

    const devFundContract = timeToken.connect(devFund);
    await devFundContract.transfer(
      await user1.getAddress(),
      ethers.parseUnits("500", 18)
    );
    await devFundContract.transfer(
      await user2.getAddress(),
      ethers.parseUnits("500", 18)
    );

    await increaseTime(ONE_HOUR_SECONDS * 2);
    await timeToken.mintBatch();

    await devFundContract.transfer(
      await user1.getAddress(),
      ethers.parseUnits("3500", 18)
    );
    await devFundContract.transfer(
      await user2.getAddress(),
      ethers.parseUnits("3500", 18)
    );

    const user1Token = timeToken.connect(user1);
    const user2Token = timeToken.connect(user2);
    await user1Token.stake(1);
    await user2Token.stake(1);

    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    const user1Balance = await timeToken.balanceOf(await user1.getAddress());
    const user2Balance = await timeToken.balanceOf(await user2.getAddress());
    const devBalAfter = await timeToken.balanceOf(await devFund.getAddress());

    const secondMintBigInt = ethers.toBigInt(ethers.parseUnits("7200", 18));
    const thirdMintBigInt = ethers.toBigInt(ethers.parseUnits("3600", 18)); 
    const totalTransfersBigInt = ethers.toBigInt(ethers.parseUnits("8000", 18));
    const devBalBeforeBigInt = ethers.toBigInt(devBalBefore);

    const expectedFinalDevBalance = devBalBeforeBigInt + secondMintBigInt + thirdMintBigInt - totalTransfersBigInt;

    expect(devBalAfter).to.be.closeTo(expectedFinalDevBalance, ethers.parseUnits("10", 18));
    expect(user1Balance).to.be.gt(0);
    expect(user2Balance).to.be.gt(0);

    console.log("User1 final balance:", user1Balance.toString());
    console.log("User2 final balance:", user2Balance.toString());
    console.log("Dev final balance:", devBalAfter.toString());
  });

  it("Scenario 3: Supply validation", async () => {
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatchValidated();

    const [valid, totalSecs, expectedSupply, currentSupply, diff] = await timeToken.validateSupply();
    console.log("Validation results:", {
      valid,
      totalSecs: totalSecs.toString(),
      expectedSupply: expectedSupply.toString(),
      currentSupply: currentSupply.toString(),
      diff: diff.toString(),
    });

    expect(Number(diff)).to.be.lessThanOrEqual(1e14);
  });

  it("Scenario 4: Multiple stakers batch alignment test", async () => {
    await increaseTime(ONE_HOUR_SECONDS * 2);
    await timeToken.mintBatch();

    const devFundToken = timeToken.connect(devFund);
    await devFundToken.transfer(
      await user1.getAddress(),
      ethers.parseUnits("1000", 18)
    );

    await increaseTime(ONE_HOUR_SECONDS * 2);
    await timeToken.mintBatch();

    await devFundToken.transfer(
      await user1.getAddress(),
      ethers.parseUnits("3000", 18)
    );
    await timeToken.connect(user1).stake(1);

    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    await devFundToken.transfer(
      await user2.getAddress(),
      ethers.parseUnits("1000", 18)
    );
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();
    
    await devFundToken.transfer(
      await user2.getAddress(),
      ethers.parseUnits("3000", 18)
    );
    await timeToken.connect(user2).stake(1);

    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatchValidated();

    const [valid] = await timeToken.validateSupply();
    expect(valid).to.equal(true);
  });

  it("Scenario 5: Distribution test", async () => {
    // Generate tokens
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // Transfer stake tokens to user
    const devFundToken = timeToken.connect(devFund);
    await devFundToken.transfer(
      await user1.getAddress(),
      STAKE_UNIT
    );

    // Record pre-stake balances
    const devPreStakeBalance = await timeToken.balanceOf(await devFund.getAddress());
    const userPreStakeBalance = await timeToken.balanceOf(await user1.getAddress());

    // User stakes
    await timeToken.connect(user1).stake(1);

    // First batch - 100% dev because of _lastBatchStakeHours = 0
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // Second batch - 30/70 split applies now
    await increaseTime(ONE_HOUR_SECONDS);
    await timeToken.mintBatch();

    // Check final state
    const devFinalBalance = await timeToken.balanceOf(await devFund.getAddress());
    const userFinalBalance = await timeToken.balanceOf(await user1.getAddress());
    const contractBalance = await timeToken.balanceOf(timeToken.getAddress());

    console.log("Balances:", {
      devPre: ethers.formatUnits(devPreStakeBalance, 18),
      devPost: ethers.formatUnits(devFinalBalance, 18),
      userPre: ethers.formatUnits(userPreStakeBalance, 18),
      userPost: ethers.formatUnits(userFinalBalance, 18),
      contract: ethers.formatUnits(contractBalance, 18)
    });

    // Contract should hold stake
    expect(contractBalance).to.equal(STAKE_UNIT);

    // User should have less (staked their tokens)
    expect(userFinalBalance).to.be.lt(userPreStakeBalance);

    // After two batches, dev should have more tokens than before
    expect(devFinalBalance).to.be.gt(devPreStakeBalance);
  });
});