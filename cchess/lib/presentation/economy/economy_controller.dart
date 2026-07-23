import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/remote/economy_api_source.dart';
import '../../data/models/economy_models.dart';
import '../../data/repositories/economy_repository.dart';
import '../shop/shop_controller.dart';

/// Providers + action surface for the S16 economy extension (D4 Hộp Thư /
/// D5 Sự Kiện / D6 Phúc Lợi / D7 Đúc Bàn Cờ). Mirrors the shop controller:
/// reads are FutureProviders over the repository (backend → cache), mutations
/// go through [EconomyController] which re-syncs the wallet/inventory
/// providers the rest of the app watches.

final mailProvider = FutureProvider.autoDispose<List<MailMessage>>((ref) {
  return ref.watch(economyRepositoryProvider).mail();
});

/// Unread/unclaimed badge count for the Explore hub tile.
final unreadMailCountProvider = Provider.autoDispose<int>((ref) {
  final mail = ref.watch(mailProvider).valueOrNull ?? const <MailMessage>[];
  return mail.where((m) => !m.read || m.hasUnclaimedReward).length;
});

final eventsProvider = FutureProvider.autoDispose<List<EconEvent>>((ref) {
  return ref.watch(economyRepositoryProvider).events();
});

/// Claimed gift keys (`eventId__giftId`) of the signed-in user.
final eventClaimsProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  return ref.watch(economyRepositoryProvider).eventClaims();
});

final welfareProvider = FutureProvider.autoDispose<WelfareStatus>((ref) {
  return ref.watch(economyRepositoryProvider).welfare();
});

final craftRecipesProvider =
    FutureProvider.autoDispose<List<CraftRecipe>>((ref) {
  return ref.watch(economyRepositoryProvider).recipes();
});

/// Mutations, keeping wallet/inventory/mail/welfare providers in sync so every
/// screen (including the shop + explore banner) reflects the credit at once.
class EconomyController {
  EconomyController(this._ref, this._repo);

  final Ref _ref;
  final EconomyRepository _repo;

  Future<ClaimOutcome> claimMail(String mailId) async {
    final outcome = await _repo.claimMail(mailId);
    _ref.invalidate(mailProvider);
    _syncWallet(itemsGranted: outcome.reward.items.isNotEmpty);
    return outcome;
  }

  Future<void> markMailRead(String mailId) async {
    await _repo.markMailRead(mailId);
    _ref.invalidate(mailProvider);
  }

  Future<void> deleteMail(String mailId) async {
    await _repo.deleteMail(mailId);
    _ref.invalidate(mailProvider);
  }

  Future<ClaimOutcome> claimEventGift(String eventId, String giftId) async {
    final outcome = await _repo.claimEventGift(eventId, giftId);
    _ref.invalidate(eventClaimsProvider);
    _syncWallet(itemsGranted: outcome.reward.items.isNotEmpty);
    return outcome;
  }

  Future<WelfareClaimOutcome> checkin() => _welfareClaim(_repo.checkin);

  Future<WelfareClaimOutcome> claimNewbie() => _welfareClaim(_repo.claimNewbie);

  Future<WelfareClaimOutcome> claimComeback() =>
      _welfareClaim(_repo.claimComeback);

  Future<CraftOutcome> craft(String recipeId) async {
    final outcome = await _repo.craft(recipeId);
    _syncWallet(itemsGranted: true);
    return outcome;
  }

  Future<WelfareClaimOutcome> _welfareClaim(
    Future<WelfareClaimOutcome> Function() call,
  ) async {
    final outcome = await call();
    _ref.invalidate(welfareProvider);
    _syncWallet(itemsGranted: outcome.reward.items.isNotEmpty);
    return outcome;
  }

  void _syncWallet({required bool itemsGranted}) {
    _ref.invalidate(walletProvider);
    if (itemsGranted) _ref.invalidate(inventoryProvider);
  }
}

final economyControllerProvider = Provider<EconomyController>((ref) {
  return EconomyController(ref, ref.watch(economyRepositoryProvider));
});
