import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';

import '../domain/billing_contracts.dart';

final class PlayBillingGateway implements BillingStoreGateway {
  PlayBillingGateway({InAppPurchase? purchases})
    : _purchases = purchases ?? InAppPurchase.instance;

  final InAppPurchase _purchases;
  final _offers = <String, (BillingOffer, GooglePlayProductDetails, String)>{};
  final _purchaseDetails = <String, GooglePlayPurchaseDetails>{};
  String? _packageName;
  String? _accountIdentifier;
  bool _disposed = false;

  @override
  Stream<List<BillingPurchase>> get purchases => _purchases.purchaseStream.map(
    (details) => [
      for (final detail in details)
        if (detail is GooglePlayPurchaseDetails) _purchase(detail),
    ],
  );

  @override
  Future<bool> isAvailable() async =>
      !_disposed &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      await _purchases.isAvailable();

  @override
  Future<List<BillingOffer>> loadOffers(BillingCatalog catalog) async {
    if (_disposed || catalog.packageName != 'com.lexiquest.app') _unavailable();
    final response = await _purchases.queryProductDetails(
      catalog.products.map((product) => product.productId).toSet(),
    );
    if (_disposed || response.error != null) _unavailable();
    final result = <String, (BillingOffer, GooglePlayProductDetails, String)>{};
    for (final details
        in response.productDetails.whereType<GooglePlayProductDetails>()) {
      final index = details.subscriptionIndex;
      final subscriptions = details.productDetails.subscriptionOfferDetails;
      if (index == null ||
          subscriptions == null ||
          index < 0 ||
          index >= subscriptions.length) {
        continue;
      }
      final subscription = subscriptions[index];
      if (subscription.offerId != null ||
          subscription.installmentPlanDetails != null ||
          subscription.pricingPhases.length != 1 ||
          subscription.pricingPhases.single.recurrenceMode !=
              RecurrenceMode.infiniteRecurring ||
          !catalog.products.any(
            (product) =>
                product.productId == details.id &&
                product.basePlanId == subscription.basePlanId,
          )) {
        continue;
      }
      final price = subscription.pricingPhases.single;
      if (price.formattedPrice.isEmpty ||
          price.formattedPrice.length > 128 ||
          details.title.isEmpty ||
          details.title.length > 256 ||
          price.billingPeriod.isEmpty ||
          price.billingPeriod.length > 32) {
        _unavailable();
      }
      final key = sha256
          .convert(
            utf8.encode(
              jsonEncode([
                details.id,
                subscription.basePlanId,
                subscription.offerIdToken,
                catalog.accountIdentifier,
              ]),
            ),
          )
          .toString();
      final offer = BillingOffer(
        offerKey: key,
        productId: details.id,
        basePlanId: subscription.basePlanId,
        title: details.title,
        localizedPrice: price.formattedPrice,
        billingPeriod: price.billingPeriod,
      );
      result[key] = (offer, details, catalog.accountIdentifier);
    }
    _offers
      ..clear()
      ..addAll(result);
    _packageName = catalog.packageName;
    _accountIdentifier = catalog.accountIdentifier;
    return List.unmodifiable(result.values.map((value) => value.$1));
  }

  @override
  Future<bool> buy(
    BillingOffer offer, {
    required String accountIdentifier,
  }) async {
    final issued = _offers[offer.offerKey];
    if (_disposed ||
        issued == null ||
        !identical(issued.$1, offer) ||
        issued.$3 != accountIdentifier) {
      _unavailable();
    }
    try {
      return await _purchases.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: issued.$2,
          applicationUserName: accountIdentifier,
          offerToken: issued.$2.offerToken,
        ),
      );
    } on Object {
      _unavailable();
    }
  }

  @override
  Future<void> restore({required String accountIdentifier}) async {
    if (_disposed || _accountIdentifier != accountIdentifier) _unavailable();
    try {
      await _purchases.restorePurchases(applicationUserName: accountIdentifier);
    } on Object {
      _unavailable();
    }
  }

  @override
  Future<void> complete(BillingPurchase purchase) async {
    final native = _purchaseDetails[purchase.storeIdentity];
    if (_disposed ||
        native == null ||
        native.billingClientPurchase.purchaseToken != purchase.purchaseToken ||
        !const {
          BillingPurchaseStatus.purchased,
          BillingPurchaseStatus.restored,
        }.contains(purchase.status)) {
      _unavailable();
    }
    try {
      if (native.pendingCompletePurchase) {
        await _purchases.completePurchase(native);
      }
      _purchaseDetails.remove(purchase.storeIdentity);
    } on Object {
      _unavailable();
    }
  }

  BillingPurchase _purchase(GooglePlayPurchaseDetails details) {
    final native = details.billingClientPurchase;
    final identity = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              native.packageName,
              details.productID,
              native.purchaseToken,
            ]),
          ),
        )
        .toString();
    if (_purchaseDetails.length >= 128 &&
        !_purchaseDetails.containsKey(identity)) {
      _purchaseDetails.remove(_purchaseDetails.keys.first);
    }
    _purchaseDetails[identity] = details;
    final status = native.packageName != (_packageName ?? 'com.lexiquest.app')
        ? BillingPurchaseStatus.failed
        : switch (details.status) {
            PurchaseStatus.pending => BillingPurchaseStatus.pending,
            PurchaseStatus.purchased => BillingPurchaseStatus.purchased,
            PurchaseStatus.restored => BillingPurchaseStatus.restored,
            PurchaseStatus.canceled => BillingPurchaseStatus.cancelled,
            PurchaseStatus.error => BillingPurchaseStatus.failed,
          };
    return BillingPurchase(
      productId: details.productID,
      status: status,
      purchaseToken: native.purchaseToken,
      accountIdentifier: native.obfuscatedAccountId,
      pendingCompletion: details.pendingCompletePurchase,
      storeIdentity: identity,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _offers.clear();
    _purchaseDetails.clear();
  }

  static Never _unavailable() =>
      throw const BillingException(BillingFailureCode.unavailable);
}
