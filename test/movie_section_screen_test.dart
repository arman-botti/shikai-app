import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/screens/movie_section_screen.dart';

void main() {
  testWidgets('MovieSectionScreen renders grid and filters correctly', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const items = [
      MovieboxItem(
        id: '1',
        title: 'Trending Movie 1',
        subjectType: 1,
        year: '2026',
        rating: 8.5,
      ),
      MovieboxItem(
        id: '2',
        title: 'Trending Series 1',
        subjectType: 2,
        year: '2025',
        rating: 9.0,
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: MovieSectionScreen(
          title: 'Trending',
          initialItems: items,
          isTrending: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Trending Movie 1'), findsOneWidget);
    expect(find.text('Trending Series 1'), findsOneWidget);

    // Switch to Series filter
    await tester.tap(find.text('TV Series'));
    await tester.pump();

    expect(find.text('Trending Series 1'), findsOneWidget);
    expect(find.text('Trending Movie 1'), findsNothing);

    // Switch to Movies filter
    await tester.tap(find.text('Movies'));
    await tester.pump();

    expect(find.text('Trending Movie 1'), findsOneWidget);
    expect(find.text('Trending Series 1'), findsNothing);
  });
}
