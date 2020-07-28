const Migrations = artifacts.require('./Migrations.sol');
const MooniFactory = artifacts.require('./MooniFactory.sol');
// const Mooniswap = artifacts.require('./Mooniswap.sol');

module.exports = function (deployer) {
    deployer.deploy(Migrations);
    deployer.deploy(MooniFactory);
    // deployer.deploy(Mooniswap);
};
