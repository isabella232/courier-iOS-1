@testable import CourierCore
@testable import CourierMQTT
import XCTest

class MQTTCourierClientTests: XCTestCase {
    var sut: MQTTCourierClient!
    var mockConnectionServiceProvider: MockConnectionServiceProvider!
    var mockSubscriptionStore: MockSubscriptionStore!
    var mockEventHandler: MockMulticastCourierEventHandler!
    var mockAuthRetryPolicy: MockAuthRetryPolicy!
    var mockMessageAdapter: MockMessageAdapter!
    var mockClient: MockMQTTClient!
    var mockMessageListener: MockMessageReceiveListener!
    var cancellables = Set<AnyCancellable>()
    let pingInterval = 30

    struct Person: Codable {
        let name: String
    }

    struct PersonError: Decodable {}

    override func setUp() {
        mockConnectionServiceProvider = MockConnectionServiceProvider()
        mockSubscriptionStore = MockSubscriptionStore()
        mockEventHandler = MockMulticastCourierEventHandler()
        mockAuthRetryPolicy = MockAuthRetryPolicy()
        mockMessageAdapter = MockMessageAdapter()
        mockClient = MockMQTTClient()
        mockMessageListener = MockMessageReceiveListener()
        
        mockClient.stubbedMessageReceiverListener = mockMessageListener

        let subscriptionStoreFactory = MockSubscriptionStoreFactory()
        subscriptionStoreFactory.stubbedMakeStoreResult = mockSubscriptionStore

        let multicastEventHandlerFactory = MockMulticastCourierEventHandlerFactory()
        multicastEventHandlerFactory.stubbedMakeHandlerResult = mockEventHandler

        let mqttClientFactory = MockMQTTClientFactory()
        mqttClientFactory.stubbedMakeClientResult = mockClient
        
        let clientConfig = MQTTClientConfig(
            topics: stubbedTopicsDict,
            authService: mockConnectionServiceProvider,
            messageAdapters: [mockMessageAdapter]
        )
        
        sut = MQTTCourierClient(
            config: clientConfig,
            subscriptionStoreFactory: subscriptionStoreFactory,
            multicastEventHandlerFactory: multicastEventHandlerFactory,
            mqttClientFactory: mqttClientFactory,
            authRetryPolicy: mockAuthRetryPolicy
        )
    }

    func testInitializationAddAsCourierEventHandler() {
        XCTAssertEqual(mockEventHandler.invokedAddEventHandlerCount, 1)
        XCTAssertTrue(mockEventHandler.invokedAddEventHandlerParametersList.last!.handler === sut)
    }

    func testConnectWhenAlreadyConnected() {
        mockClient.stubbedIsConnected = true
        sut.connect()
        if case .connectionServiceAuthStart = self.mockEventHandler.invokedOnEventParameters?.event {
            XCTAssert(false)
        }
        
        XCTAssertFalse(mockConnectionServiceProvider.invokedGetConnectOptions)
    }

    func testConnect() {
        sut.connect()
//        XCTAssertTrue(mockEventHandler.invokedReset)
        if case .connectionServiceAuthStart = self.mockEventHandler.invokedOnEventParameters?.event {
            XCTAssert(true)
        } else {
            XCTAssert(false)
        }
        XCTAssertTrue(mockConnectionServiceProvider.invokedGetConnectOptions)
    }

    func testConnectAlreadyConnected() {
        mockClient.stubbedIsConnected = true
        XCTAssertFalse(mockEventHandler.invokedReset)
        
        if case .connectionServiceAuthStart = self.mockEventHandler.invokedOnEventParameters?.event {
            XCTAssert(false)
        }
        XCTAssertFalse(mockConnectionServiceProvider.invokedGetConnectOptions)
    }

    func testConnectWithSuccessCredentials() {
        mockConnectionServiceProvider.stubbedGetConnectOptionsCompletionResult = (.success(stubConnectOptions), ())
        sut.connect()
        if case let .connectionServiceAuthSuccess(host, port, _) = self.mockEventHandler.invokedOnEventParameters?.event {
            XCTAssertEqual(host, stubConnectOptions.host)
            XCTAssertEqual(port, Int(stubConnectOptions.port))
        } else {
            XCTAssert(false)
        }
        XCTAssertTrue(mockAuthRetryPolicy.invokedResetParams)
        XCTAssertTrue(mockClient.invokedReset)
        XCTAssertTrue(mockClient.invokedConnect)

        XCTAssertEqual(mockClient.invokedConnectParameters?.connectOptions.host, stubConnectOptions.host)

        XCTAssertEqual(mockClient.invokedConnectParameters?.connectOptions.port, UInt16(stubConnectOptions.port))
        XCTAssertEqual(mockClient.invokedConnectParameters?.connectOptions.keepAlive, UInt16(pingInterval))
        XCTAssertEqual(mockClient.invokedConnectParameters?.connectOptions.clientId, stubConnectOptions.clientId)
        XCTAssertEqual(mockClient.invokedConnectParameters?.connectOptions.username, stubConnectOptions.username)
        XCTAssertEqual(mockClient.invokedConnectParameters?.connectOptions.password, stubConnectOptions.password)
    }

    func testConnectWithFailureCredentials() {
        mockConnectionServiceProvider.stubbedGetConnectOptionsCompletionResult = (.failure(stubbedError), ())
        mockAuthRetryPolicy.stubbedGetRetryTimeResult = 0.1

        sut.connect()
        if case .connectionServiceAuthFailure = self.mockEventHandler.invokedOnEventParametersList[1]?.event {
            XCTAssert(true)
        } else {
            XCTAssert(false)
        }
        
        if case .connectionUnavailable = self.mockEventHandler.invokedOnEventParametersList[2]?.event {
            XCTAssert(true)
        } else {
            XCTAssert(false)
        }
        XCTAssertTrue(mockAuthRetryPolicy.invokedShouldRetry)
    }

    func testSubscribeTopics() {
        sut.subscribe(stubbedTopics)
        XCTAssertTrue(mockSubscriptionStore.invokedSubscribe)
        XCTAssertTrue(mockClient.invokedSubscribe)
    }

    func testSubscribeTopic() {
        sut.subscribe(("fbon", qos: .zero))
        XCTAssertTrue(mockSubscriptionStore.invokedSubscribe)
        XCTAssertTrue(mockClient.invokedSubscribe)
    }

    func testPublishMessage() {
        let person = Person(name: "gojek")
        let data = try! JSONEncoder().encode(person)
        mockMessageAdapter.stubbedToMessageResult = data
        mockClient.stubbedHasExistingSession = true
        XCTAssertNoThrow(try sut.publishMessage(person, topic: "fbon", qos: .two))
        XCTAssert(mockClient.invokedSend)
        XCTAssertTrue(mockMessageAdapter.invokedToMessage)
        XCTAssertEqual(mockClient.invokedSendParameters?.packet.qos, .two)
        XCTAssertEqual(mockClient.invokedSendParameters?.packet.topic, "fbon")
        XCTAssertEqual(mockClient.invokedSendParameters?.packet.data, data)
    }
    
    func testPublishMessageWithoutExistingSession() {
        let person = Person(name: "gojek")
        let data = try! JSONEncoder().encode(person)
        mockMessageAdapter.stubbedToMessageResult = data
        mockClient.stubbedHasExistingSession = false
        XCTAssertThrowsError(try sut.publishMessage(person, topic: "fbon", qos: .two))
        XCTAssertFalse(mockClient.invokedSend)
        XCTAssertFalse(mockMessageAdapter.invokedToMessage)
    }

    func testExistingUnsubscribeTopics() {
        sut.unsubscribe(["fbon5"])
        XCTAssertTrue(mockSubscriptionStore.invokedUnsubscribe)
        XCTAssertTrue(mockClient.invokedUnsubscribe)
        mockSubscriptionStore.stubbedIsCurrentlyPendingUnsubscribeResult = true
        sut.unsubscribe(["fbon5"])
        XCTAssertEqual(mockSubscriptionStore.invokedUnsubscribeCount, 1)
        XCTAssertEqual(mockClient.invokedUnsubscribeCount, 1)
    }

    func testExistingUnsubscribeTopic() {
        sut.unsubscribe("fbon5")
        XCTAssertTrue(mockSubscriptionStore.invokedUnsubscribe)
        XCTAssertTrue(mockClient.invokedUnsubscribe)
        mockSubscriptionStore.stubbedIsCurrentlyPendingUnsubscribeResult = true
        sut.unsubscribe("fbon5")
        XCTAssertEqual(mockClient.invokedUnsubscribeCount, 1)
    }

    func testAddEventHandler() {
        sut.addEventHandler(mockEventHandler)
        XCTAssertTrue(mockEventHandler.invokedAddEventHandler)
    }

    func testRemoveEventHandler() {
        sut.removeEventHandler(mockEventHandler)
        XCTAssertTrue(mockEventHandler.invokedRemoveEventHandler)
    }

    func testDestroy() {
        sut.destroy()
        XCTAssertTrue(mockSubscriptionStore.invokedClearAllSubscriptions)
        XCTAssertTrue(mockClient.invokedDeleteAllPersistedMessages)
        XCTAssertTrue(mockClient.invokedDestroy)
        XCTAssertTrue(mockClient.invokedMessageReceiverListenerGetter)
    }

    func testHandleAuthFailure() {
        sut.handleAuthFailure()
//        XCTAssertTrue(mockEventHandler.invokedReset)
        if case .connectionServiceAuthStart = self.mockEventHandler.invokedOnEventParameters?.event {
            XCTAssert(true)
        } else {
            XCTAssert(false)
        }
        XCTAssertTrue(mockConnectionServiceProvider.invokedGetConnectOptions)
    }

    func testOnConnectAttempt() {
        testPublishConnectionState {
            sut.onEvent(.connectionAttempt)
        }
    }

    func testOnConnectionSuccess() {
        testPublishConnectionState {
            sut.onEvent(.connectionSuccess)
            XCTAssertTrue(mockClient.invokedSubscribe)
        }
    }

    func testOnConnectionFailure() {
        testPublishConnectionState {
            sut.onEvent(.connectionFailure(error: nil))
        }
    }

    func testOnConnectionLost() {
        testPublishConnectionState {
            sut.onEvent(.connectionLost(error: nil, diffLastInbound: nil, diffLastOutbound: nil))
        }
    }

    func testOnConnectionDisconnect() {
        testPublishConnectionState {
            sut.onEvent(.connectionDisconnect)
        }
    }

    func testOnAppForegroundConnect() {
        sut.onEvent(.appForeground)
        let expectation_ = expectation(description: "test")
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            expectation_.fulfill()
        }
        waitForExpectations(timeout: 0.1) { _ in
//            XCTAssertTrue(self.mockEventHandler.invokedReset)
            if case .connectionServiceAuthStart = self.mockEventHandler.invokedOnEventParameters?.event {
                XCTAssert(true)
            } else {
                XCTAssert(false)
            }
            XCTAssertTrue(self.mockConnectionServiceProvider.invokedGetConnectOptions)
        }
    }

    func testOnConnectionAvailableConnect() {
        mockSubscriptionStore.stubbedSubscriptions = stubbedTopicsDict
        sut.onEvent(.connectionAvailable)
        let expectation_ = expectation(description: "test")
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            expectation_.fulfill()
        }
        waitForExpectations(timeout: 0.1) { _ in
//            XCTAssertTrue(self.mockEventHandler.invokedReset)
            if case .connectionServiceAuthStart = self.mockEventHandler.invokedOnEventParameters?.event {
                XCTAssert(true)
            } else {
                XCTAssert(false)
            }
            XCTAssertTrue(self.mockConnectionServiceProvider.invokedGetConnectOptions)
        }
    }

    func testMessageReceiveStream() {
        mockClient.stubbedSubscribedMessageStream = PublishSubject<MQTTPacket>().asObservable()
        sut.messagePublisher(topic: "test")
            .sink { (_: Person) in }
            .store(in: &cancellables)
        XCTAssertTrue(mockClient.invokedSubscribedMessageStreamGetter)
    }

    func testMessageReceiveStreamWithErrorDecodeHandler() {
        mockClient.stubbedSubscribedMessageStream = PublishSubject<MQTTPacket>().asObservable()
        sut.messagePublisher(topic: "test") { (_: PersonError) -> Error in
            NSError(domain: "x", code: 1, userInfo: [:])
        }
        .sink { (_: Result<Person, NSError>) in
        }.store(in: &cancellables)

        XCTAssertTrue(mockClient.invokedSubscribedMessageStreamGetter)
    }
    
    func testGetUserNameModifierWithoutModification() {
        let usernameModifier = sut.getUsernameModifier(isUsernameModificationEnabled: false, countryCodeProvider: {"ID"})
        XCTAssertTrue(usernameModifier is DefaultUserNameModifier)
    }
    
    func testGetUserNameModifierWithModifiaction() {
        let usernameModifier = sut.getUsernameModifier(isUsernameModificationEnabled: true, countryCodeProvider: {"ID"})
        XCTAssertTrue(usernameModifier is UserNameModifier)
    }
    
    func testConnectSource() {
        sut.connect(source: "Gojek")
        XCTAssertEqual(sut.connectSource, "Gojek")
    }
    
}

extension MQTTCourierClientTests {
    func testPublishConnectionState(invocation: () -> Void) {
        mockClient.stubbedIsConnected = true
        let exp = expectation(description: "connect")
        sut.connectionStatePublisher
            .sink { state in
                XCTAssertEqual(state, .connected)
                exp.fulfill()
            }.store(in: &cancellables)

        invocation()
        waitForExpectations(timeout: 0.1, handler: nil)
    }

    var stubbedTopicsDict: [String: QoS] {
        [
            "fbon": .zero,
            "fbon2": .two
        ]
    }
    
    var stubbedTopics: [(String, QoS)] {
        [
            ("fbon", .zero),
            ("fbon2", .two)
        ]
    }
    
    var stubConnectOptions: ConnectOptions {
        ConnectOptions(
            host: "hyz",
            port: 999,
            keepAlive: 30,
            clientId: "xyz",
            username: "abc",
            password: "token",
            isCleanSession: true
        )
    }
    
    var stubbedError: AuthError {
        .otherError(NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost, userInfo: [:]))
    }
}


