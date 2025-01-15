import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployChickenFarm: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // Get TTB address
  const TTB = await deployments.get('TimeTickBase');

  // 1. Deploy the dual wrapper
  const wrapper = await deploy('TTBDualWrapper_V2', {
    from: deployer,
    args: [
      TTB.address,
      "🐔 Chicken Token",
      "CHKN",
      "🥚 Fresh Egg",
      "EGG",
      1,    // 1:1 for CHKN
      1000  // 1:1000 for EGG
    ],
    log: true,
    waitConfirmations: 1,
  });

  // 2. Get CHKN token address from wrapper
  const DualWrapper = await hre.ethers.getContractFactory('TTBDualWrapper_V2');
  const wrapperContract = DualWrapper.attach(wrapper.address);
  const chknAddress = await wrapperContract.TOKEN_A();

  // 3. Deploy the farm
  const farm = await deploy('ChickenFarm_V2', {
    from: deployer,
    args: [wrapper.address, chknAddress],
    log: true,
    waitConfirmations: 1,
  });

  // 4. Set farm as authorized minter
  await wrapperContract.setAuthorizedMinter(farm.address);
  console.log(`Set ChickenFarm (${farm.address}) as authorized minter for eggs`);
};

deployChickenFarm.tags = ['ChickenFarm_V2'];
deployChickenFarm.dependencies = ['TimeTickBase'];

export default deployChickenFarm;