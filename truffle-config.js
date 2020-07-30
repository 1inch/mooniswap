module.exports = {
    compilers: {
        solc: {
            version: '0.6.12',
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 1000000,
                }
            }
        },
    },
    plugins: ["solidity-coverage"],
    mocha: { // https://github.com/cgewecke/eth-gas-reporter
        reporter: 'eth-gas-reporter',
        reporterOptions : {
            currency: 'USD',
            gasPrice: 10,
            onlyCalledMethods: true,
            showTimeSpent: true,
            excludeContracts: ['Migrations', 'mocks']
        }
    }
};
