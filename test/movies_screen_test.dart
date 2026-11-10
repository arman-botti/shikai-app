import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/screens/movies_screen.dart';

void main() {
  testWidgets('MoviesScreen renders shelves and filters without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const home = MovieboxHome(
      banners: [
        MovieboxItem(
          id: '1',
          title: 'Hero Movie',
          subjectType: 1,
          year: '2026',
          rating: 8.2,
          genre: 'Action, Adventure',
        ),
      ],
      sections: [
        MovieboxHomeSection(
          title: 'Trending Now',
          type: 'SUBJECTS_MOVIE',
          items: [
            MovieboxItem(id: '1', title: 'Hero Movie', subjectType: 1, year: '2026', rating: 8.2),
            MovieboxItem(id: '2', title: 'Series One', subjectType: 2, year: '2025', rating: 7.5),
            MovieboxItem(id: '4', title: 'Another Movie', subjectType: 1, year: '2024'),
            MovieboxItem(id: '5', title: 'Third Movie', subjectType: 1, year: '2023'),
          ],
        ),
        MovieboxHomeSection(
          title: 'Only Series',
          type: 'SUBJECTS_MOVIE',
          items: [
            MovieboxItem(id: '3', title: 'Series Two', subjectType: 2, year: '2024'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MoviesScreen(
          homeLoader: ({bool forceRefresh = false}) async => home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('MOVIES'), findsOneWidget);
    expect(find.text('Trending Now'), findsOneWidget);
    expect(find.text('Hero Movie'), findsWidgets);
    expect(find.text('Series One'), findsOneWidget);

    await tester.tap(find.text('TV Series'));
    await tester.pump();
    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pump();

    expect(find.text('Only Series'), findsOneWidget);
    expect(find.text('Series Two'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
