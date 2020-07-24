const Migrations = artifacts.require('./Migrations.sol');
// const Mooniswap = artifacts.require('./Mooniswap.sol');

module.exports = function (deployer) {
    deployer.deploy(Migrations);
    // deployer.deploy(Mooniswap);
};
