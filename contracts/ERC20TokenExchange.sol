pragma solidity ^0.4.23;


import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/payment/PullPayment.sol";
import "openzeppelin-solidity/contracts/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";


contract ERC20TokenExchange is PullPayment, ReentrancyGuard {

    using SafeMath for uint256;

    event SellOrderPut(address _erc20TokenAddress, address _seller, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);
    event SellOrderFilled(address _erc20TokenAddress, address _seller, address _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);

    event BuyOrderPut(address _erc20TokenAddress, address _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);
    event BuyOrderFilled(address _erc20TokenAddress, address _buyer, address _seller, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _numOfLot);

	struct Order {

		uint256 tokenPerLot;
		uint256 pricePerLot;
		uint256 numOfLot;

	}

    mapping(address => mapping(address => Order)) public sellOrders;
    mapping(address => mapping(address => Order)) public buyOrders;

    function () public payable {
    	require(msg.value != 0);
    	asyncSend(msg.sender, msg.value);
    }

    function putSellOrder(address _erc20TokenAddress, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToSell) public nonReentrant {

    	require(_erc20TokenAddress != address(0));
		require(_tokenPerLot != 0);
		require(_pricePerLot != 0);
		require(_lotToSell != 0);

    	Order storage order = sellOrders[_erc20TokenAddress][msg.sender];
    	order.tokenPerLot = _tokenPerLot;
		order.pricePerLot = _pricePerLot;
		order.numOfLot = _lotToSell;

    	ERC20 erc20 = ERC20(_erc20TokenAddress);
    	require(hasSufficientTokenInternal(erc20, msg.sender, _lotToSell.mul(_tokenPerLot)));

    	emit SellOrderPut(_erc20TokenAddress, msg.sender, _tokenPerLot, _pricePerLot, _lotToSell);
    }

    function fillSellOrder(address _erc20TokenAddress, address _seller, uint256 _tokenPerLot, uint256 _lotToBuy) public payable nonReentrant {

    	require(_erc20TokenAddress != address(0));
		require(_seller != address(0));
		require(_lotToBuy != 0);

    	Order storage order = sellOrders[_erc20TokenAddress][_seller];
    	uint256 numOfLot = order.numOfLot;
    	uint256 pricePerLot = order.pricePerLot;
    	require(numOfLot >= _lotToBuy);
    	require(order.tokenPerLot == _tokenPerLot);

    	uint256 payment = pricePerLot.mul(_lotToBuy);
    	require(payment != 0 && payment == msg.value);

    	order.numOfLot = numOfLot.sub(_lotToBuy);

    	asyncSend(_seller, payment);

    	ERC20 erc20 = ERC20(_erc20TokenAddress);

		uint256 amoutToBuy = _lotToBuy.mul(_tokenPerLot);
    	uint256 previousBalance = erc20.balanceOf(msg.sender);
    	
    	SafeERC20.safeTransferFrom(erc20, _seller, msg.sender, amoutToBuy);
    	require(previousBalance.add(amoutToBuy) == erc20.balanceOf(msg.sender));
    	
    	emit SellOrderFilled(_erc20TokenAddress, _seller, msg.sender, _tokenPerLot, pricePerLot, _lotToBuy);
    }

    function putBuyOrder(address _erc20TokenAddress, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToBuy) public nonReentrant {

    	require(_erc20TokenAddress != address(0));
		require(_tokenPerLot != 0);
		require(_pricePerLot != 0);
		require(_lotToBuy != 0);
		require(hasSufficientPaymentInternal(msg.sender, _pricePerLot.mul(_lotToBuy)));

    	Order storage order = buyOrders[_erc20TokenAddress][msg.sender];
    	order.tokenPerLot = _tokenPerLot;
		order.pricePerLot = _pricePerLot;
		order.numOfLot = _lotToBuy;

    	emit BuyOrderPut(_erc20TokenAddress, msg.sender, _tokenPerLot, _pricePerLot, _lotToBuy);
    }

    function fillBuyOrder(address _erc20TokenAddress, address _buyer, uint256 _tokenPerLot, uint256 _pricePerLot, uint256 _lotToSell) public nonReentrant {
    	require(_erc20TokenAddress != address(0));
    	require(_buyer != address(0));
		require(_tokenPerLot != 0);
		require(_pricePerLot != 0);
		require(_lotToSell != 0);

    	Order storage order = buyOrders[_erc20TokenAddress][_buyer];
        uint256 numOfLot = order.numOfLot;

    	require(numOfLot >= _lotToSell);
    	require(order.tokenPerLot == _tokenPerLot);
    	require(order.pricePerLot == _pricePerLot);

    	uint256 payment = _pricePerLot.mul(_lotToSell);

    	asyncTransfer(_buyer, msg.sender, payment);
    	order.numOfLot = numOfLot.sub(_lotToSell);

    	ERC20 erc20 = ERC20(_erc20TokenAddress);

    	uint256 amoutToSell = _lotToSell.mul(_tokenPerLot);
    	uint256 previousBalance = erc20.balanceOf(_buyer);

    	SafeERC20.safeTransferFrom(erc20, msg.sender, _buyer, amoutToSell);
    	require(previousBalance.add(amoutToSell) == erc20.balanceOf(_buyer));

    	emit SellOrderFilled(_erc20TokenAddress, _buyer, msg.sender, _tokenPerLot, _pricePerLot, _lotToSell);
    }

    function isValidSellOrder(address _erc20TokenAddress, address _seller) public view returns(bool) {
    	ERC20 erc20 = ERC20(_erc20TokenAddress);
    	Order storage order = sellOrders[_erc20TokenAddress][_seller];
    	return hasSufficientTokenInternal(erc20, _seller, order.tokenPerLot.mul(order.numOfLot));
    }

    function isValidBuyOrder(address _erc20TokenAddress, address _buyer) public view returns(bool) {
    	Order storage order = buyOrders[_erc20TokenAddress][_buyer];
		return hasSufficientPaymentInternal(_buyer, order.pricePerLot.mul(order.numOfLot));
    }

    function getSellOrderInfo(address _erc20TokenAddress, address _seller) public view returns(uint256, uint256, uint256) {
    	Order storage order = sellOrders[_erc20TokenAddress][_seller];
    	return (order.tokenPerLot, order.pricePerLot, order.numOfLot);
    }

    function getBuyOrderInfo(address _erc20TokenAddress, address _buyer) public view returns(uint256, uint256, uint256) {
    	Order storage order = buyOrders[_erc20TokenAddress][_buyer];
    	return (order.tokenPerLot, order.pricePerLot, order.numOfLot);
    }

    function asyncTransfer(address _from, address _to, uint256 amount) internal {
    	require(hasSufficientPaymentInternal(_from, amount));
    	payments[_from] = payments[_from].sub(amount);
    	payments[_to] = payments[_to].add(amount);
    }

    function hasSufficientPaymentInternal(address _payee, uint256 _amount) internal view returns(bool) {
		return payments[_payee] >= _amount;
    }

    function hasSufficientTokenInternal(ERC20 erc20, address _seller, uint256 _amountToSell) internal view returns(bool) {
    	return erc20.allowance(_seller, address(this)) >= _amountToSell;
    }

}