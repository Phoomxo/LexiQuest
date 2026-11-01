import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:vocab_learning_app/features/billing/data/play_billing_gateway.dart';
import 'package:vocab_learning_app/features/billing/domain/billing_contracts.dart';

void main() {
  test(
    'real Play SDK mapping uses exact allowlisted base-plan offer and localized price',
    () async {
      final native = _Purchases();
      final gateway = PlayBillingGateway(purchases: native);
      addTearDown(() async {
        await gateway.dispose();
        await native.events.close();
      });
      native.products = GooglePlayProductDetails.fromProductDetails(_product());
      final offers = await gateway.loadOffers(_catalog());
      expect(offers, hasLength(1));
      expect(offers.single.basePlanId, 'monthly');
      expect(offers.single.localizedPrice, '฿99.00');
      await gateway.buy(offers.single, accountIdentifier: 'a' * 64);
      final parameter = native.parameter! as GooglePlayPurchaseParam;
      expect(parameter.applicationUserName, 'a' * 64);
      expect(parameter.offerToken, 'synthetic-ordinary-monthly');
      expect(parameter.productDetails.id, 'synthetic.subscription');
    },
  );

  test(
    'a copied or cross-account offer cannot launch a native purchase',
    () async {
      final native = _Purchases();
      final gateway = PlayBillingGateway(purchases: native);
      addTearDown(() async {
        await gateway.dispose();
        await native.events.close();
      });
      native.products = GooglePlayProductDetails.fromProductDetails(_product());
      final offer = (await gateway.loadOffers(_catalog())).single;
      await expectLater(
        () => gateway.buy(offer, accountIdentifier: 'b' * 64),
        throwsA(isA<BillingException>()),
      );
      final copied = BillingOffer(
        offerKey: offer.offerKey,
        productId: offer.productId,
        basePlanId: offer.basePlanId,
        title: offer.title,
        localizedPrice: offer.localizedPrice,
        billingPeriod: offer.billingPeriod,
      );
      await expectLater(
        () => gateway.buy(copied, accountIdentifier: 'a' * 64),
        throwsA(isA<BillingException>()),
      );
      expect(native.parameter, isNull);
    },
  );

  test(
    'restore remains available when an existing subscription has no current sale offer',
    () async {
      final native = _Purchases();
      final gateway = PlayBillingGateway(purchases: native);
      addTearDown(() async {
        await gateway.dispose();
        await native.events.close();
      });
      expect(await gateway.loadOffers(_catalog()), isEmpty);
      await gateway.restore(accountIdentifier: 'a' * 64);
      expect(native.restoredAccount, 'a' * 64);
    },
  );

  test(
    'native receipt mapping redacts identity and completes only its original purchase',
    () async {
      final native = _Purchases();
      final gateway = PlayBillingGateway(purchases: native);
      addTearDown(() async {
        await gateway.dispose();
        await native.events.close();
      });
      final receipt = PurchaseWrapper(
        orderId: 'synthetic-order',
        packageName: 'com.lexiquest.app',
        purchaseTime: 1,
        purchaseToken: 'synthetic-private-token',
        signature: 'synthetic-signature',
        products: const ['synthetic.subscription'],
        isAutoRenewing: true,
        originalJson: '{}',
        isAcknowledged: false,
        purchaseState: PurchaseStateWrapper.purchased,
        obfuscatedAccountId: 'a' * 64,
      );
      final result = gateway.purchases.first;
      native.events.add(GooglePlayPurchaseDetails.fromPurchase(receipt));
      final purchase = (await result).single;
      expect(purchase.status, BillingPurchaseStatus.purchased);
      expect(purchase.accountIdentifier, 'a' * 64);
      expect(purchase.toString(), isNot(contains(receipt.purchaseToken)));
      await gateway.complete(purchase);
      expect(native.completed, hasLength(1));
    },
  );
}

BillingCatalog _catalog() => BillingCatalog(
  packageName: 'com.lexiquest.app',
  policyRevision: 'synthetic-v1',
  accountIdentifier: 'a' * 64,
  products: [
    BillingProduct(
      productId: 'synthetic.subscription',
      basePlanId: 'monthly',
      entitlements: {'managedContent'},
    ),
  ],
);

ProductDetailsWrapper _product() => ProductDetailsWrapper(
  description: 'Synthetic only',
  name: 'Synthetic',
  productId: 'synthetic.subscription',
  productType: ProductType.subs,
  title: 'Synthetic subscription',
  subscriptionOfferDetails: [
    _offer('yearly', token: 'synthetic-yearly'),
    _offer('monthly', offerId: 'trial', token: 'synthetic-trial'),
    _offer('monthly', token: 'synthetic-ordinary-monthly'),
  ],
);

SubscriptionOfferDetailsWrapper _offer(
  String plan, {
  String? offerId,
  required String token,
}) => SubscriptionOfferDetailsWrapper(
  basePlanId: plan,
  offerId: offerId,
  offerTags: const [],
  offerIdToken: token,
  pricingPhases: const [
    PricingPhaseWrapper(
      billingCycleCount: 0,
      billingPeriod: 'P1M',
      formattedPrice: '฿99.00',
      priceAmountMicros: 99000000,
      priceCurrencyCode: 'THB',
      recurrenceMode: RecurrenceMode.infiniteRecurring,
    ),
  ],
);

class _Purchases implements InAppPurchase {
  final events = StreamController<List<PurchaseDetails>>.broadcast();
  List<ProductDetails> products = [];
  PurchaseParam? parameter;
  String? restoredAccount;
  final completed = <PurchaseDetails>[];
  @override
  Stream<List<PurchaseDetails>> get purchaseStream => events.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async => ProductDetailsResponse(productDetails: products, notFoundIDs: []);
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    parameter = purchaseParam;
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restoredAccount = applicationUserName;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
