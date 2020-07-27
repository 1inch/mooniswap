const { time, ether, expectRevert } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const money = {
    ether,
    zero: ether('0'),
    weth: ether,
    dai: ether,
    usdc: (value) => ether(value).divn(1e12),
};

async function trackReceivedToken (token, wallet, txPromise) {
    const preBalance = web3.utils.toBN(await token.balanceOf(wallet));
    await txPromise();
    const postBalance = web3.utils.toBN(await token.balanceOf(wallet));
    return postBalance.sub(preBalance);
}

async function timeIncreaseTo (seconds) {
    const delay = 1000 - new Date().getMilliseconds();
    await new Promise(resolve => setTimeout(resolve, delay));
    await time.increaseTo(seconds);
}

async function checkBalances (mooniswap, token, expectedBalance, expectedAdditionBalance, expectedRemovalBalance) {
    const balance = await token.balanceOf(mooniswap.address);
    const additionBalance = await mooniswap.getBalanceForAddition(token.address);
    const removalBalance = await mooniswap.getBalanceForRemoval(token.address);
    expect(balance).to.be.bignumber.equal(expectedBalance);
    expect(additionBalance).to.be.bignumber.equal(expectedAdditionBalance);
    expect(removalBalance).to.be.bignumber.equal(expectedRemovalBalance);
}

const Mooniswap = artifacts.require('Mooniswap');
const TokenMock = artifacts.require('TokenMock');

contract('Mooniswap', function ([_, wallet1, wallet2]) {
    beforeEach(async function () {
        this.DAI = await TokenMock.new('DAI', 'DAI', 18);
        this.WETH = await TokenMock.new('WETH', 'WETH', 18);
        this.USDC = await TokenMock.new('USDC', 'USDC', 6);
    });

    describe('Creation', async function () {
        it('should be denied with tokens length not eqaul to 2', async function () {
            await expectRevert(
                Mooniswap.new([], 'Mooniswap', 'MOON'),
                'Mooniswap: only 2 tokens allowed',
            );

            await expectRevert(
                Mooniswap.new([this.WETH.address], 'Mooniswap', 'MOON'),
                'Mooniswap: only 2 tokens allowed',
            );

            await expectRevert(
                Mooniswap.new([this.WETH.address, this.DAI.address, this.USDC.address], 'Mooniswap', 'MOON'),
                'Mooniswap: only 2 tokens allowed',
            );
        });

        it('should be denied with token duplicates', async function () {
            await expectRevert(
                Mooniswap.new([this.WETH.address, this.WETH.address], 'Mooniswap', 'MOON'),
                'Mooniswap: duplicate tokens',
            );
        });

        it('should be denied with empty name', async function () {
            await expectRevert(
                Mooniswap.new([this.WETH.address, this.DAI.address], '', 'MOON'),
                'Mooniswap: name is empty',
            );
        });

        it('should be denied with empty symbol', async function () {
            await expectRevert(
                Mooniswap.new([this.WETH.address, this.DAI.address], 'Mooniswap', ''),
                'Mooniswap: symbol is empty',
            );
        });

        it('should be allowed for 2 different tokens and non-empty name and symbol', async function () {
            await Mooniswap.new([this.WETH.address, this.DAI.address], 'Mooniswap', 'MOON');
        });
    });

    describe('Actions', async function () {
        beforeEach(async function () {
            this.mooniswap = await Mooniswap.new([this.WETH.address, this.DAI.address], 'Mooniswap', 'MOON');
            await this.WETH.mint(wallet1, money.weth('1'));
            await this.DAI.mint(wallet1, money.dai('270'));
            await this.WETH.mint(wallet2, money.weth('10'));
            await this.DAI.mint(wallet2, money.dai('2700'));
            await this.WETH.approve(this.mooniswap.address, money.weth('1'), { from: wallet1 });
            await this.DAI.approve(this.mooniswap.address, money.dai('270'), { from: wallet1 });
            await this.WETH.approve(this.mooniswap.address, money.weth('10'), { from: wallet2 });
            await this.DAI.approve(this.mooniswap.address, money.dai('2700'), { from: wallet2 });
        });

        describe('Initial deposits', async function () {
            it('should be denied with length not equal to 2', async function () {
                await expectRevert(
                    this.mooniswap.deposit([], money.zero, { from: wallet1 }),
                    'Mooniswap: wrong amounts length',
                );

                await expectRevert(
                    this.mooniswap.deposit([money.weth('1')], money.zero, { from: wallet1 }),
                    'Mooniswap: wrong amounts length',
                );

                await expectRevert(
                    this.mooniswap.deposit([money.weth('1'), money.dai('270'), money.dai('1')], money.zero, { from: wallet1 }),
                    'Mooniswap: wrong amounts length',
                );
            });

            it('should be denied for zero amount', async function () {
                await expectRevert(
                    this.mooniswap.deposit([money.weth('0'), money.dai('270')], money.zero, { from: wallet1 }),
                    'Mooniswap: amount is zero',
                );

                await expectRevert(
                    this.mooniswap.deposit([money.weth('1'), money.dai('0')], money.zero, { from: wallet1 }),
                    'Mooniswap: amount is zero',
                );
            });

            it('should be denied for not enough minReturn', async function () {
                await expectRevert(
                    this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('271'), { from: wallet1 }),
                    'Mooniswap: result is not enough',
                );
            });

            it('should be allowed with zero minReturn', async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.zero, { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));
            });

            it('should be allowed with strict minReturn', async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));
            });

            it('should give the same shares for the same deposits', async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));

                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet2 });
                expect(await this.mooniswap.balanceOf(wallet2)).to.be.bignumber.equal(money.dai('270'));
            });

            it('should give the proportional shares for the proportional deposits', async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));

                await this.mooniswap.deposit([money.weth('10'), money.dai('2700')], money.dai('2700'), { from: wallet2 });
                expect(await this.mooniswap.balanceOf(wallet2)).to.be.bignumber.equal(money.dai('2700'));
            });

            it('should give the right shares for the repeated deposits', async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));

                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet2 });
                expect(await this.mooniswap.balanceOf(wallet2)).to.be.bignumber.equal(money.dai('270'));

                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet2 });
                expect(await this.mooniswap.balanceOf(wallet2)).to.be.bignumber.equal(money.dai('540'));
            });

            it('should give less share on unbalanced deposits', async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));

                await this.mooniswap.deposit([money.weth('1'), money.dai('271')], money.dai('270'), { from: wallet2 });
                expect(await this.mooniswap.balanceOf(wallet2)).to.be.bignumber.equal(money.dai('270'));
                expect(await this.DAI.balanceOf(wallet2)).to.be.bignumber.equal(money.dai('2429'));
            });
        });

        describe('Swaps', async function () {
            beforeEach(async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));
                await timeIncreaseTo((await time.latest()).add(await this.mooniswap.decayPeriod()));
            });

            it('should give 50% of tokenB for 100% of tokenA swap as designed by x*y=k', async function () {
                const wethAdditionBalance = await this.mooniswap.getBalanceForAddition(this.WETH.address);
                const daiRemovalBalance = await this.mooniswap.getBalanceForRemoval(this.DAI.address);
                const result = await this.mooniswap.getReturn(this.WETH.address, this.DAI.address, money.weth('1'));
                expect(wethAdditionBalance).to.be.bignumber.equal(money.weth('1'));
                expect(daiRemovalBalance).to.be.bignumber.equal(money.dai('270'));
                expect(result).to.be.bignumber.equal(money.dai('135'));

                const received = await trackReceivedToken(
                    this.DAI,
                    wallet2,
                    () => this.mooniswap.swap(this.WETH.address, this.DAI.address, money.weth('1'), money.zero, { from: wallet2 }),
                );
                expect(received).to.be.bignumber.equal(money.dai('135'));
            });

            it('should be give additive results for the swaps of the same direction', async function () {
                // Pre-second swap checks
                const wethAdditionBalance1 = await this.mooniswap.getBalanceForAddition(this.WETH.address);
                const daiRemovalBalance1 = await this.mooniswap.getBalanceForRemoval(this.DAI.address);
                const result1 = await this.mooniswap.getReturn(this.WETH.address, this.DAI.address, money.weth('0.5'));
                expect(wethAdditionBalance1).to.be.bignumber.equal(money.weth('1'));
                expect(daiRemovalBalance1).to.be.bignumber.equal(money.dai('270'));
                expect(result1).to.be.bignumber.equal(money.dai('90'));

                // The first swap of 0.5 WETH to DAI
                const received1 = await trackReceivedToken(
                    this.DAI,
                    wallet2,
                    () => this.mooniswap.swap(this.WETH.address, this.DAI.address, money.weth('0.5'), money.zero, { from: wallet2 }),
                );
                expect(received1).to.be.bignumber.equal(money.dai('90'));

                // Pre-second swap checks
                const wethAdditionBalance2 = await this.mooniswap.getBalanceForAddition(this.WETH.address);
                const daiRemovalBalance2 = await this.mooniswap.getBalanceForRemoval(this.DAI.address);
                const result2 = await this.mooniswap.getReturn(this.WETH.address, this.DAI.address, money.weth('0.5'));
                expect(wethAdditionBalance2).to.be.bignumber.equal(money.weth('1.5'));
                expect(daiRemovalBalance2).to.be.bignumber.equal(money.dai('180'));
                expect(result2).to.be.bignumber.equal(money.dai('45'));

                // The second swap of 0.5 WETH to DAI
                const received2 = await trackReceivedToken(
                    this.DAI,
                    wallet2,
                    () => this.mooniswap.swap(this.WETH.address, this.DAI.address, money.weth('0.5'), money.zero, { from: wallet2 }),
                );
                expect(received2).to.be.bignumber.equal(money.dai('45'));

                // Two 0.5 WETH swaps are equal to the 1 WETH swap
                expect(received1.add(received2)).to.be.bignumber.equal(money.dai('135'));
            });

            it('should affect reverse price', async function () {
                // Pre-second swap checks
                const wethAdditionBalance1 = await this.mooniswap.getBalanceForAddition(this.WETH.address);
                const daiRemovalBalance1 = await this.mooniswap.getBalanceForRemoval(this.DAI.address);
                const result1 = await this.mooniswap.getReturn(this.WETH.address, this.DAI.address, money.weth('1'));
                expect(wethAdditionBalance1).to.be.bignumber.equal(money.weth('1'));
                expect(daiRemovalBalance1).to.be.bignumber.equal(money.dai('270'));
                expect(result1).to.be.bignumber.equal(money.dai('135'));

                const started = (await time.latest()).addn(10);
                await timeIncreaseTo(started);

                // The first swap of 1 WETH to 135 DAI
                const received1 = await trackReceivedToken(
                    this.DAI,
                    wallet2,
                    () => this.mooniswap.swap(this.WETH.address, this.DAI.address, money.weth('1'), money.zero, { from: wallet2 }),
                );
                expect(received1).to.be.bignumber.equal(money.dai('135'));

                // Checks at the start of the decay period
                const daiAdditionBalance2 = await this.mooniswap.getBalanceForAddition(this.DAI.address);
                const wethRemovalBalance2 = await this.mooniswap.getBalanceForRemoval(this.WETH.address);
                const result2 = await this.mooniswap.getReturn(this.DAI.address, this.WETH.address, money.dai('270'));
                expect(daiAdditionBalance2).to.be.bignumber.equal(money.weth('270'));
                expect(wethRemovalBalance2).to.be.bignumber.equal(money.dai('1'));
                expect(result2).to.be.bignumber.equal(money.weth('0.5'));

                await timeIncreaseTo(started.add((await this.mooniswap.decayPeriod()).divn(2)));

                // Checks at the middle of the decay period
                const daiAdditionBalance3 = await this.mooniswap.getBalanceForAddition(this.DAI.address);
                const wethRemovalBalance3 = await this.mooniswap.getBalanceForRemoval(this.WETH.address);
                const result3 = await this.mooniswap.getReturn(this.DAI.address, this.WETH.address, money.dai('202.5'));
                expect(daiAdditionBalance3).to.be.bignumber.equal(money.dai('202.5'));
                expect(wethRemovalBalance3).to.be.bignumber.equal(money.weth('1.5'));
                expect(result3).to.be.bignumber.equal(money.weth('0.75'));

                await timeIncreaseTo(started.add(await this.mooniswap.decayPeriod()));

                // Checks at the end of the decay period
                const daiAdditionBalance4 = await this.mooniswap.getBalanceForAddition(this.DAI.address);
                const wethRemovalBalance4 = await this.mooniswap.getBalanceForRemoval(this.WETH.address);
                const result4 = await this.mooniswap.getReturn(this.DAI.address, this.WETH.address, money.dai('135'));
                expect(daiAdditionBalance4).to.be.bignumber.equal(money.dai('135'));
                expect(wethRemovalBalance4).to.be.bignumber.equal(money.weth('2'));
                expect(result4).to.be.bignumber.equal(money.weth('1'));

                // swap back 135 DAI to 1 ETH
                const received2 = await trackReceivedToken(
                    this.WETH,
                    wallet2,
                    () => this.mooniswap.swap(this.DAI.address, this.WETH.address, money.dai('135'), money.zero, { from: wallet2 }),
                );
                expect(received2).to.be.bignumber.equal(money.weth('1'));
            });

            it('should do multiple cross swaps', async function () {
                const started = (await time.latest()).addn(10);
                await timeIncreaseTo(started);

                expect(await trackReceivedToken(
                    this.DAI,
                    wallet2,
                    () => this.mooniswap.swap(
                        this.WETH.address,
                        this.DAI.address,
                        money.weth('1'),
                        money.zero,
                        { from: wallet2 },
                    ),
                )).to.be.bignumber.equal(money.dai('135'));

                await checkBalances(this.mooniswap, this.WETH, money.weth('2'), money.weth('2'), money.weth('1'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('135'), money.dai('270'), money.dai('135'));

                expect(await trackReceivedToken(
                    this.WETH,
                    wallet2,
                    () => this.mooniswap.swap(
                        this.DAI.address,
                        this.WETH.address,
                        money.dai('270'),
                        money.zero,
                        { from: wallet2 },
                    ),
                )).to.be.bignumber.equal(money.weth('0.5'));

                await checkBalances(this.mooniswap, this.WETH, money.weth('1.5'), money.weth('2'), money.weth('0.5'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('405'), money.dai('540'), money.dai('135'));

                await timeIncreaseTo(started.add((await this.mooniswap.decayPeriod()).divn(2)));

                await checkBalances(this.mooniswap, this.WETH, money.weth('1.5'), money.weth('1.75'), money.weth('1'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('405'), money.dai('472.5'), money.dai('270'));

                expect(await trackReceivedToken(
                    this.DAI,
                    wallet2,
                    () => this.mooniswap.swap(
                        this.WETH.address,
                        this.DAI.address,
                        money.weth('1.75'),
                        money.zero,
                        { from: wallet2 },
                    ),
                )).to.be.bignumber.equal(money.dai('135'));

                await checkBalances(this.mooniswap, this.WETH, money.weth('3.25'), money.weth('3.5'), money.weth('1'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('270'), money.dai('472.5'), money.dai('135'));

                expect(await trackReceivedToken(
                    this.WETH,
                    wallet2,
                    () => this.mooniswap.swap(
                        this.DAI.address,
                        this.WETH.address,
                        money.dai('472.5'),
                        money.zero,
                        { from: wallet2 },
                    ),
                )).to.be.bignumber.equal(money.weth('0.5'));

                await checkBalances(this.mooniswap, this.WETH, money.weth('2.75'), money.weth('3.5'), money.weth('0.5'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('742.5'), money.dai('945'), money.dai('135'));
            });
        });

        describe('Deposits after swaps', async function () {
            beforeEach(async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));
                await timeIncreaseTo((await time.latest()).add(await this.mooniswap.decayPeriod()));
            });

            it('should deposit imbalanced amount after swap', async function () {
                const started = (await time.latest()).addn(10);
                await timeIncreaseTo(started);

                await this.mooniswap.swap(this.WETH.address, this.DAI.address, money.weth('1'), money.zero, { from: wallet2 });

                await timeIncreaseTo(started.add((await this.mooniswap.decayPeriod()).divn(2)));

                const received2 = await trackReceivedToken(
                    this.mooniswap,
                    wallet2,
                    () => this.mooniswap.deposit(
                        [money.weth('2'), money.dai('135')],
                        money.ether('270'),
                        { from: wallet2 },
                    ),
                );

                expect(received2).to.be.bignumber.equal(money.dai('270'));
            });

            it('should not update rates after imbalanced deposit', async function () {
                const started = (await time.latest()).addn(10);
                await timeIncreaseTo(started);

                await this.mooniswap.swap(this.WETH.address, this.DAI.address, money.weth('1'), money.zero, { from: wallet2 });

                await checkBalances(this.mooniswap, this.WETH, money.weth('2'), money.weth('2'), money.weth('1'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('135'), money.dai('270'), money.dai('135'));

                await timeIncreaseTo(started.add((await this.mooniswap.decayPeriod()).divn(2)));

                await checkBalances(this.mooniswap, this.WETH, money.weth('2'), money.weth('2'), money.weth('1.5'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('135'), money.dai('202.5'), money.dai('135'));

                const received = await trackReceivedToken(
                    this.mooniswap,
                    wallet2,
                    () => this.mooniswap.deposit(
                        [money.weth('2'), money.dai('135')],
                        money.ether('270'),
                        { from: wallet2 },
                    ),
                );
                expect(received).to.be.bignumber.equal(money.dai('270'));

                await checkBalances(this.mooniswap, this.WETH, money.weth('4'), money.weth('2'), money.weth('1.5'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('270'), money.dai('202.5'), money.dai('135'));

                // swap back 135 DAI to 1 ETH
                const received2 = await trackReceivedToken(
                    this.WETH,
                    wallet2,
                    () => this.mooniswap.swap(
                        this.DAI.address,
                        this.WETH.address,
                        money.dai('101.25'),
                        money.zero,
                        { from: wallet2 },
                    ),
                );
                expect(received2).to.be.bignumber.equal(money.weth('0.5'));

                await checkBalances(this.mooniswap, this.WETH, money.weth('3.5'), money.weth('2'), money.weth('1'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('371.25'), money.dai('303.75'), money.dai('135'));
            });

            it('should decrease losses on imbalanced deposit', async function () {
                const started = (await time.latest()).addn(10);
                await timeIncreaseTo(started);
                const received = await trackReceivedToken(
                    this.mooniswap,
                    wallet2,
                    () => this.mooniswap.deposit(
                        [money.weth('1'), money.dai('270')],
                        money.ether('270'),
                        { from: wallet2 },
                    ),
                );
                expect(received).to.be.bignumber.equal(money.dai('270'));

                // Pool contains 2 WETH and 540 DAI.
                // Real price is 1 WETH for 540 DAI so there is an arbitrage opportunity to buy cheap ether.
                // Simple Uniswap would settle amounts at DAI = 763.675, WETH = 1.414
                // Slow deposit should save more in the pool

                await timeIncreaseTo(started.add((await this.mooniswap.decayPeriod()).divn(2)));

                await checkBalances(this.mooniswap, this.WETH, money.weth('2'), money.weth('1.5'), money.weth('1.5'));
                await checkBalances(this.mooniswap, this.DAI, money.dai('540'), money.dai('405'), money.dai('405'));

                const received2 = await trackReceivedToken(
                    this.WETH,
                    wallet2,
                    () => this.mooniswap.swap(
                        this.DAI.address,
                        this.WETH.address,
                        money.dai('168'),
                        money.zero,
                        { from: wallet2 },
                    ),
                );
                expect(received2).to.be.bignumber.equal('439790575916230366');

                await timeIncreaseTo(started.add((await this.mooniswap.decayPeriod()).muln(2)));

                await checkBalances(this.mooniswap, this.WETH, '1560209424083769634', '1560209424083769634', '1560209424083769634');
                await checkBalances(this.mooniswap, this.DAI, money.dai('708'), money.dai('708'), money.dai('708'));

                await trackReceivedToken(
                    this.WETH,
                    wallet2,
                    () => this.mooniswap.swap(
                        this.DAI.address,
                        this.WETH.address,
                        money.dai('56'),
                        money.zero,
                        { from: wallet2 },
                    ),
                );

                const daiBalance = await this.DAI.balanceOf(this.mooniswap.address);
                const wethBalance = await this.WETH.balanceOf(this.mooniswap.address);
                expect(daiBalance).to.be.bignumber.equal(money.dai('764')); // Uniswap balance would be 763.675
                expect(wethBalance).to.be.bignumber.gt(money.weth('1.445')); // Uniswap balance would be 1.414
            });
        });

        describe('Withdrawals', async function () {
            beforeEach(async function () {
                await this.mooniswap.deposit([money.weth('1'), money.dai('270')], money.dai('270'), { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('270'));
                await timeIncreaseTo((await time.latest()).add(await this.mooniswap.decayPeriod()));
            });

            it('should be able to exit fully', async function () {
                await this.mooniswap.withdraw(money.dai('270'), [], { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.zero);
                expect(await this.DAI.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.zero);
                expect(await this.WETH.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.zero);
            });

            it('should be able to exit partially', async function () {
                await this.mooniswap.withdraw(money.dai('135'), [], { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.dai('135'));
                expect(await this.DAI.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.dai('135'));
                expect(await this.WETH.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.weth('0.5'));

                await this.mooniswap.withdraw(money.dai('135'), [], { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.zero);
                expect(await this.DAI.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.zero);
                expect(await this.WETH.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.zero);
            });

            it('2 users should be able to exit', async function () {
                await this.mooniswap.deposit(
                    [money.weth('1'), money.dai('270')],
                    money.ether('270'),
                    { from: wallet2 },
                );

                await this.mooniswap.withdraw(money.dai('270'), [], { from: wallet1 });
                expect(await this.mooniswap.balanceOf(wallet1)).to.be.bignumber.equal(money.zero);
                expect(await this.DAI.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.dai('270'));
                expect(await this.WETH.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.weth('1'));

                await this.mooniswap.withdraw(money.dai('270'), [], { from: wallet2 });
                expect(await this.mooniswap.balanceOf(wallet2)).to.be.bignumber.equal(money.zero);
                expect(await this.DAI.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.zero);
                expect(await this.WETH.balanceOf(this.mooniswap.address)).to.be.bignumber.equal(money.zero);
            });
        });
    });
});
