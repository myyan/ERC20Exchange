const MockToken = artifacts.require('MockToken')
const ERC20TokenExchange = artifacts.require('ERC20TokenExchange')

contract('ERC20TokenExchange', accounts => {

	const account0 = accounts[0];
	const account1 = accounts[1];
	const account2 = accounts[2];
	const account3 = accounts[3];

	it('Should approve', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		await token.mint(account0, 100000000000);

		await token.approve(exchange.address, 2000, {
			from: account0
		});

		var allowanceToken = await token.allowance.call(account0, exchange.address);
		assert.equal(allowanceToken.toNumber(), 2000);

	})

	it('Should not put sell order without sufficient allowance', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var errorThrown = false;
		try {
			await exchange.putSellOrder(token.address, 1000, 1000, 3, {
				from: account0
			})
		} catch (err) {
			errorThrown = true;
		}
		assert(errorThrown, 'Expected throw not received');

	})


	it('Should not fill sell order before valid order', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var errorThrown = false;
		try {
			await exchange.fillSellOrder(token.address, account0, 1000, 1, {
				from: account1,
				value: 1000
			})
		} catch (err) {
			errorThrown = true;
		}
		assert(errorThrown, 'Expected throw not received');

	})


	it('Should put sell order with sufficient allowance', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		await exchange.putSellOrder(token.address, 1000, 1000, 2, {
			from: account0
		})

	})

	it('Should update sell order', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		await exchange.putSellOrder(token.address, 100, 10000, 20, {
			from: account0
		})

	})

	it('Should not fill sell order over limit', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var errorThrown = false;
		try {
			await exchange.fillSellOrder(token.address, account0, 100, 21, {
				from: account1,
				value: 210000
			})
		} catch (err) {
			errorThrown = true;
		}
		assert(errorThrown, 'Expected throw not received');

	})

	it('Should not fill sell order with incorrect lot size', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var errorThrown = false;
		try {
			await exchange.fillSellOrder(token.address, account0, 1000, 1, {
				from: account1,
				value: 10000
			})
		} catch (err) {
			errorThrown = true;
		}
		assert(errorThrown, 'Expected throw not received');

	})

	it('Should not fill sell order with incorrect payment', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var errorThrown = false;
		try {
			await exchange.fillSellOrder(token.address, account0, 100, 1, {
				from: account1,
				value: 1000
			})
		} catch (err) {
			errorThrown = true;
		}
		assert(errorThrown, 'Expected throw not received');

	})

	it('Should fill sell order with correct payment', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var account1Token = await token.balanceOf.call(account1);
		assert.equal(account1Token.toNumber(), 0);

		await exchange.fillSellOrder(token.address, account0, 100, 10, {
			from: account1,
			value: 100000
		})

		account1Token = await token.balanceOf.call(account1);
		assert.equal(account1Token.toNumber(), 1000);

		var allowanceToken = await token.allowance.call(account0, exchange.address);
		assert.equal(allowanceToken.toNumber(), 1000);

		await exchange.fillSellOrder(token.address, account0, 100, 10, {
			from: account1,
			value: 100000
		})

		account1Token = await token.balanceOf.call(account1);
		assert.equal(account1Token.toNumber(), 2000);

		allowanceToken = await token.allowance.call(account0, exchange.address);
		assert.equal(allowanceToken.toNumber(), 0);

	})

	it('Should not fill sell order with zero lot', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var errorThrown = false;
		try {
			await exchange.fillSellOrder(token.address, account0, 100, 10, {
				from: account1,
				value: 100000
			})
		} catch (err) {
			errorThrown = true;
		}
		assert(errorThrown, 'Expected throw not received');

	})

	it('Should not put buy order with insufficient deposit', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var errorThrown = false;
		try {
			await exchange.putBuyOrder(token.address, 1000, 1000, 2, {
				from: account2
			})
		} catch (err) {
			errorThrown = true;
		}
		assert(errorThrown, 'Expected throw not received');

	})

	it('Should deposit ether before putting buyer order', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		await exchange.sendTransaction({
			from: account2,
			value: 2000
		});

	})

	it('Should put buy order with sufficient deposit', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		await exchange.putBuyOrder(token.address, 1000, 1000, 2, {
			from: account2
		})

	})

	it('Should approve token before filling buy order', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		await token.mint(account3, 100000000000);

		await token.approve(exchange.address, 2000, {
			from: account3
		});

		var allowanceToken = await token.allowance.call(account3, exchange.address);
		assert.equal(allowanceToken.toNumber(), 2000);

	})

	it('Should fill buy order', async function () {

		const token = await MockToken.deployed();
		const exchange = await ERC20TokenExchange.deployed();

		var account1Token = await token.balanceOf.call(account2);
		assert.equal(account1Token.toNumber(), 0);

		await exchange.fillBuyOrder(token.address, account2, 1000, 1000, 2, {
			from: account3
		})

		account1Token = await token.balanceOf.call(account2);
		assert.equal(account1Token.toNumber(), 2000);

		var allowanceToken = await token.allowance.call(account3, exchange.address);
		assert.equal(allowanceToken.toNumber(), 0);

	})


})