// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DecentralizedCarRental {

    uint256 public nextCarId;

    struct Car {
        uint256 carId;
        bool isscooter;
        address payable owner;
        string locate;
        string model;
        string plate;
        uint256 pricePerHour;
        uint256 fdcanstart;
        uint256 ldcanstart;
        bool isOnline;
    }

    struct RentalInfo {
        address payable renter;
        uint256 startTimestamp;
        uint256 endTimestamp;
        uint256 ftotalCost;
        bool isActive;
        bool renterConfirmed;
        bool ownerConfirmed;
        bool extraFeePaid;
    }

    mapping(uint256 => Car) public cars;       // 車輛資料
    mapping(uint256 => RentalInfo) public rentals;  // 租借紀錄
    mapping(address => uint256[]) public ownerToCarIds; // 車主擁有的車輛 IDs

    // 事件
    event CarListed(uint256 carId, address indexed owner, string model, string plate, uint256 pricePerHour);
    event CarAvailabilityUpdated(uint256 carId, bool isOnline);
    event CarRented(uint256 carId, address indexed renter, uint256 rentstart, uint256 rentend, uint256 totalCost);
    event RentalStart(uint256 carId, address indexed renter);
    event RentalEnded(uint256 carId, address indexed renter);
    event ExtraCharged(uint256 carId, address renter, uint256 extraHours, uint256 extraCost);

    // -------------------
    // 車主功能
    // -------------------

    /// 車主上架車輛
    function addCar(
        bool _isscooter,
        string memory _locate,
        string memory _model,
        string memory _plate,
        uint256 _pricePerHour,
        uint256 _fdcanstart,
        uint256 _ldcanstart
    ) external {
        require(_pricePerHour > 0, "Price must be greater than zero");
        require(_ldcanstart > _fdcanstart, "lastday must be after firstday");

        cars[nextCarId] = Car({
            carId: nextCarId,
            isscooter: _isscooter,
            owner: payable(msg.sender),
            locate: _locate,
            model: _model,
            plate: _plate,
            fdcanstart: _fdcanstart,
            ldcanstart: _ldcanstart,
            pricePerHour: _pricePerHour,
            isOnline: true
        });

        ownerToCarIds[msg.sender].push(nextCarId);
        emit CarListed(nextCarId, msg.sender, _model, _plate, _pricePerHour);

        nextCarId++;
    }

    /// 車主下架車輛
    function setCarAvailability(uint256 _carId, bool _isOnline) external {
        Car storage car = cars[_carId];
        require(car.owner == msg.sender, "Not the car owner");
        car.isOnline = _isOnline;
        emit CarAvailabilityUpdated(_carId, _isOnline);
    }

    // -------------------
    // 租客功能
    // -------------------

    /// @notice 租客租借車輛
    function rentCar(uint256 _carId, uint256 totalCost, uint256 rentstart, uint256 rentend) external payable{
        Car storage car = cars[_carId];
        require(car.isOnline, "Car is not available");
        require(car.owner != msg.sender, "Owner cannot rent own car");
        require(totalCost >= car.pricePerHour, "Must rent for at least 1 hour");
        require(car.fdcanstart<=rentstart, "car can not be rented");
        require(car.ldcanstart>=rentend, "over the last day can rent");
        require(msg.value >= totalCost, "Insufficient ETH sent");

        // 如果付多了就退還多餘的金額
        uint256 overpaid = msg.value - totalCost;
        if (overpaid > 0) {
            payable(msg.sender).transfer(overpaid);
        }

        // 轉帳租金給車主
        car.owner.transfer(totalCost);

        rentals[_carId] = RentalInfo({
            renter: payable(msg.sender),
            startTimestamp: rentstart,
            endTimestamp: rentend,
            ftotalCost: totalCost,
            isActive: false,
            renterConfirmed: false,
            ownerConfirmed: false,
            extraFeePaid: false
        });

        emit CarRented(_carId, msg.sender, rentstart, rentend, totalCost);
    }

     /// 車主或租客雙方確認開始租借
    function startRental(uint256 _carId) external {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];

        require(
            msg.sender == car.owner || msg.sender == rent.renter,
            "Only renter or owner can confirm start"
        );

        // 各自紀錄確認狀態
        if (msg.sender == rent.renter) {
            rent.renterConfirmed = true;
        } else if (msg.sender == car.owner) {
            rent.ownerConfirmed = true;
        }

        // 當雙方都確認，正式開始租借
        if (rent.renterConfirmed && rent.ownerConfirmed) {
            rent.isActive = true;
            emit RentalStart(_carId, rent.renter);
        }
    }

    // 結束租約且確認是否收取超時費用
    function endRental(uint256 _carId, uint256 overtimeHours) external payable {
        RentalInfo storage rent = rentals[_carId];
        Car storage car = cars[_carId];

        require(
            msg.sender == car.owner || msg.sender == rent.renter,
            "Only renter or owner can confirm return"
        );
        require(rent.isActive, "No active rental");

        if (!rent.extraFeePaid) {
        require(msg.sender == rent.renter, "Renter need to pay");
        }
        
        // 未超時即設定為已付款
        if (overtimeHours == 0) {
            rent.extraFeePaid = true;
            if (msg.value > 0) {
            payable(msg.sender).transfer(msg.value);
        }
        }

        // 如果有超時且未付款，要求付款
        if (overtimeHours > 0 && !rent.extraFeePaid) {
            uint256 extraCost = overtimeHours * car.pricePerHour;
            require(msg.value >= extraCost, "Insufficient ETH for overtime");
            // 如果付超過，退還
            uint256 refund = msg.value - extraCost;
            if (refund > 0) {
                payable(msg.sender).transfer(refund);
            }

            // 將超時費轉給車主
            car.owner.transfer(extraCost);

            rent.ftotalCost += extraCost;
            rent.extraFeePaid = true;
            emit ExtraCharged(_carId, rent.renter, overtimeHours, extraCost);
        }

        // 記錄雙方按確認
        if (msg.sender == rent.renter) {
            rent.renterConfirmed = false;
        } else if (msg.sender == car.owner) {
            rent.ownerConfirmed = false;
        }

        if (!rent.renterConfirmed && !rent.ownerConfirmed && rent.extraFeePaid) {
            rent.isActive = false;
            emit RentalEnded(_carId, rent.renter);
        }
    }

    // -------------------
    // 查詢功能
    // -------------------

    /// 取得某個車主的所有車
    function getMyCars() external view returns (uint256[] memory) {
        return ownerToCarIds[msg.sender];
    }

    /// 取得某輛車的詳細資料
    function getCar(uint256 _carId) external view returns (Car memory) {
        return cars[_carId];
    }

    /// 取得某輛車的租借資訊
    function getRental(uint256 _carId) external view returns (RentalInfo memory) {
        return rentals[_carId];
    }

    /// 查詢可租借的車 ID
    function getAvailableCars() external view returns (uint256[] memory) {
        uint256 availableCount = 0;

        for (uint256 i = 0; i < nextCarId; i++) {
            if (cars[i].isOnline) {
                availableCount++;
            }
        }

        uint256[] memory result = new uint256[](availableCount);
        uint256 index = 0;

        for (uint256 i = 0; i < nextCarId; i++) {
            if (cars[i].isOnline) {
                result[index] = i;
                index++;
            }
        }
        return result;
    }
}
