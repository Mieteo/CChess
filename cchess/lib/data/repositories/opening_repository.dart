import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/local/opening_seed.dart';
import '../models/opening.dart';

class OpeningRepository {
  List<Opening> all() => kOpenings;

  Opening? byId(String id) {
    for (final o in kOpenings) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Most popular openings first — useful for the list screen.
  List<Opening> sortedByPopularity() {
    final out = List<Opening>.from(kOpenings);
    out.sort((a, b) => b.popularity.compareTo(a.popularity));
    return out;
  }
}

final openingRepositoryProvider =
    Provider<OpeningRepository>((ref) => OpeningRepository());
