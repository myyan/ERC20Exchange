const ERC20TokenExchange = artifacts.require('ERC20TokenExchange')

module.exports = function (deployer) {

	deployer.deploy(ERC20TokenExchange);

}