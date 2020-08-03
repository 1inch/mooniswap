const { expectRevert } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const Mooniswap = artifacts.require('Mooniswap');
const MooniFactory = artifacts.require('MooniFactory');
const TokenWithBytes32SymbolMock = artifacts.require('TokenWithBytes32SymbolMock');
const TokenWithStringSymbolMock = artifacts.require('TokenWithStringSymbolMock');
const TokenWithBytes32CAPSSymbolMock = artifacts.require('TokenWithBytes32CAPSSymbolMock');
const TokenWithStringCAPSSymbolMock = artifacts.require('TokenWithStringCAPSSymbolMock');
const TokenWithNoSymbolMock = artifacts.require('TokenWithNoSymbolMock');

contract('MooniFactory', function ([_, wallet1, wallet2]) {
    beforeEach(async function () {
        this.factory = await MooniFactory.new();
    });

    describe('Symbol', async function () {
        it('should handle bytes32 symbol', async function () {
            const token1 = await TokenWithBytes32SymbolMock.new(web3.utils.toHex('ABC'));
            const token2 = await TokenWithStringSymbolMock.new('XYZ');
            await this.factory.deploy(token1.address, token2.address);

            const pool = await Mooniswap.at(await this.factory.pools(token1.address, token2.address));
            if (token1.address.localeCompare(token2.address, undefined, { sensitivity: 'base' }) < 0) {
                expect(await pool.symbol()).to.be.equal('MOON-V1-ABC-XYZ');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (ABC-XYZ)');
            } else {
                expect(await pool.symbol()).to.be.equal('MOON-V1-XYZ-ABC');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (XYZ-ABC)');
            }
        });

        it('should handle 33-char len symbol', async function () {
            const token1 = await TokenWithStringSymbolMock.new('012345678901234567890123456789123');
            const token2 = await TokenWithStringSymbolMock.new('XYZ');
            await this.factory.deploy(token1.address, token2.address);

            const pool = await Mooniswap.at(await this.factory.pools(token1.address, token2.address));
            if (token1.address.localeCompare(token2.address, undefined, { sensitivity: 'base' }) < 0) {
                expect(await pool.symbol()).to.be.equal('MOON-V1-012345678901234567890123456789123-XYZ');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (012345678901234567890123456789123-XYZ)');
            } else {
                expect(await pool.symbol()).to.be.equal('MOON-V1-XYZ-012345678901234567890123456789123');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (XYZ-012345678901234567890123456789123)');
            }
        });

        it('should handle tokens without symbol', async function () {
            const token1 = await TokenWithNoSymbolMock.new();
            const token2 = await TokenWithStringSymbolMock.new('XYZ');
            await this.factory.deploy(token1.address, token2.address);

            const pool = await Mooniswap.at(await this.factory.pools(token1.address, token2.address));
            if (token1.address.localeCompare(token2.address, undefined, { sensitivity: 'base' }) < 0) {
                expect(await pool.symbol()).to.be.equal('MOON-V1-' + token1.address.toLowerCase() + '-XYZ');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (' + token1.address.toLowerCase() + '-XYZ)');
            } else {
                expect(await pool.symbol()).to.be.equal('MOON-V1-XYZ-' + token1.address.toLowerCase());
                expect(await pool.name()).to.be.equal('Mooniswap V1 (XYZ-' + token1.address.toLowerCase() + ')');
            }
        });

        it('should handle tokens with empty string symbol', async function () {
            const token1 = await TokenWithStringSymbolMock.new('');
            const token2 = await TokenWithStringSymbolMock.new('XYZ');
            await this.factory.deploy(token1.address, token2.address);

            const pool = await Mooniswap.at(await this.factory.pools(token1.address, token2.address));
            if (token1.address.localeCompare(token2.address, undefined, { sensitivity: 'base' }) < 0) {
                expect(await pool.symbol()).to.be.equal('MOON-V1-' + token1.address.toLowerCase() + '-XYZ');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (' + token1.address.toLowerCase() + '-XYZ)');
            } else {
                expect(await pool.symbol()).to.be.equal('MOON-V1-XYZ-' + token1.address.toLowerCase());
                expect(await pool.name()).to.be.equal('Mooniswap V1 (XYZ-' + token1.address.toLowerCase() + ')');
            }
        });

        it('should handle tokens with empty bytes32 symbol', async function () {
            const token1 = await TokenWithBytes32SymbolMock.new('0x');
            const token2 = await TokenWithStringSymbolMock.new('XYZ');
            await this.factory.deploy(token1.address, token2.address);

            const pool = await Mooniswap.at(await this.factory.pools(token1.address, token2.address));
            if (token1.address.localeCompare(token2.address, undefined, { sensitivity: 'base' }) < 0) {
                expect(await pool.symbol()).to.be.equal('MOON-V1-' + token1.address.toLowerCase() + '-XYZ');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (' + token1.address.toLowerCase() + '-XYZ)');
            } else {
                expect(await pool.symbol()).to.be.equal('MOON-V1-XYZ-' + token1.address.toLowerCase());
                expect(await pool.name()).to.be.equal('Mooniswap V1 (XYZ-' + token1.address.toLowerCase() + ')');
            }
        });

        it('should handle tokens with CAPS symbol', async function () {
            const token1 = await TokenWithBytes32CAPSSymbolMock.new(web3.utils.toHex('caps1'));
            const token2 = await TokenWithStringCAPSSymbolMock.new('caps2');
            await this.factory.deploy(token1.address, token2.address);

            const pool = await Mooniswap.at(await this.factory.pools(token1.address, token2.address));
            if (token1.address.localeCompare(token2.address, undefined, { sensitivity: 'base' }) < 0) {
                expect(await pool.symbol()).to.be.equal('MOON-V1-caps1-caps2');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (caps1-caps2)');
            } else {
                expect(await pool.symbol()).to.be.equal('MOON-V1-caps2-caps1');
                expect(await pool.name()).to.be.equal('Mooniswap V1 (caps2-caps1)');
            }
        });
    });

    describe('Creation', async function () {
        it('should do not work for same token', async function () {
            const token1 = await TokenWithStringSymbolMock.new('ABC');

            await expectRevert(
                this.factory.deploy(token1.address, token1.address),
                'Factory: not support same tokens',
            );
        });

        it('should do not allow twice pool creation even flipped', async function () {
            const token1 = await TokenWithStringSymbolMock.new('ABC');
            const token2 = await TokenWithStringSymbolMock.new('XYZ');
            await this.factory.deploy(token1.address, token2.address);

            await expectRevert(
                this.factory.deploy(token1.address, token2.address),
                'Factory: pool already exists',
            );

            await expectRevert(
                this.factory.deploy(token2.address, token1.address),
                'Factory: pool already exists',
            );
        });
    });
});
