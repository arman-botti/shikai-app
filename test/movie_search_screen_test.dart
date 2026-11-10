import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/screens/movie_search_screen.dart';

void main() {
  testWidgets('MovieSearchScreen grid fits narrow screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final results = List.generate(
      9,
      (i) => MovieboxItem(
        id: '$i',
        title: 'Search Result $i',
        subjectType: i.isEven ? 1 : 2,
        year: '2026',
        rating: 7.5,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MovieSearchScreen(searchLoader: (query) async => results),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'avatar');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Search Result 0'), findsOneWidget);
    expect(find.text('Search Result 8'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
