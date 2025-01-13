import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployDualWrapper: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // Get the TTB contract address from previous deployment
  const TTB = await deployments.get('TimeTickBase');

  // Example dual wrapper parameters
  const TOKEN_A_NAME = "First Token";
  const TOKEN_A_SYMBOL = "FIRST";
  const TOKEN_B_NAME = "Second Token";
  const TOKEN_B_SYMBOL = "SECOND";
  const RATIO_A = 1;      // 1:1 with TTB
  const RATIO_B = 1000;   // 1000:1 with TTB

  const wrapper = await deploy('TTBDualWrapper', {
    from: deployer,
    args: [
      TTB.address,
      TOKEN_A_NAME,
      TOKEN_A_SYMBOL,
      TOKEN_B_NAME,
      TOKEN_B_SYMBOL,
      RATIO_A,
      RATIO_B
    ],
    log: true,
    waitConfirmations: 1,
  });

  // Optional: Set authorized minter if specified in env
  if (process.env.AUTHORIZED_MINTER) {
    const DualWrapper = await hre.ethers.getContractFactory('TTBDualWrapper');
    const dualWrapper = DualWrapper.attach(wrapper.address);
    await dualWrapper.setAuthorizedMinter(process.env.AUTHORIZED_MINTER);
    console.log(`Set authorized minter to ${process.env.AUTHORIZED_MINTER}`);
  }
};

deployDualWrapper.tags = ['TTBDualWrapper'];
deployDualWrapper.dependencies = ['TimeTickBase'];

export default deployDualWrapper;