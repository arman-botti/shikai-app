import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shikai_app/models/moviebox_media.dart';
import 'package:shikai_app/screens/movie_detail_screen.dart';

void main() {
  testWidgets('MovieDetailScreen renders series layout without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const detail = MovieboxDetail(
      id: '42',
      title: 'A Very Long MovieBox Series Title That Wraps',
      subjectType: 2,
      description:
          'This is a long description used to verify that the detail screen wraps text correctly without causing a horizontal overflow on narrow devices.',
      releaseDate: '2026-11-05',
      duration: '2h 18m',
      rating: 8.7,
      genre: 'Action, Adventure, Fantasy, Thriller',
      country: 'India',
      language: 'Hindi, English',
      dubs: [
        MovieboxDub(id: '43', name: 'Hindi dub'),
        MovieboxDub(id: '44', name: 'Tamil dub'),
        MovieboxDub(id: '45', name: 'Telugu dub'),
      ],
    );

    const seasons = [
      MovieboxSeason(season: 1, episodeCount: 8),
      MovieboxSeason(season: 2, episodeCount: 6),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MovieDetailScreen(
          subjectId: '42',
          title: detail.title,
          isSeries: true,
          detailLoader: (_) async => detail,
          seasonsLoader: (_) async => seasons,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(detail.title), findsWidgets);
    expect(find.text('SEASONS'), findsOneWidget);
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(find.text('Hindi dub'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -320));
    await tester.pump();
    await tester.tap(find.text('Season 2'));
    await tester.pump();

    expect(find.text('6'), findsOneWidget);
    expect(find.text('8'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
