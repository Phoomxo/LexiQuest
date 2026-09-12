/// Original local practice material. Levels are editorial estimates, not
/// certified CEFR assessments. No external generation or reviewer is implied.
abstract final class LocalReadingCatalog {
  static const notice =
      'บทอ่านในเครื่อง · ระดับโดยประมาณ ยังไม่ผ่านการรับรอง CEFR';

  static LocalReadingLesson forLevel(String level) => switch (level
      .trim()
      .toUpperCase()) {
    'A1' => const LocalReadingLesson(
      'local-reading-a1-r1',
      'A1',
      'A book for May',
      'May has a blue bag. A book and a pencil are in the bag. '
          'She walks to school with her friend Ben. They sit by the window. '
          'May opens her book and reads about a small dog. Ben draws the dog. '
          'After class, they put their books away and walk home together.',
      'What is in May’s bag?',
    ),
    'A2' => const LocalReadingLesson(
      'local-reading-a2-r1',
      'A2',
      'A change of plan',
      'On Saturday, Nita planned to visit a park with her brother. '
          'When they left home, it started to rain. They checked the bus map '
          'and decided to go to the library instead. Nita borrowed a book about '
          'plants, while her brother found a story about the sea. Later, the rain '
          'stopped. They ate their sandwiches outside and talked about their books.',
      'Why did Nita and her brother change their plan?',
    ),
    'B1' => const LocalReadingLesson(
      'local-reading-b1-r2',
      'B1',
      'The shared garden',
      'An empty space beside our building used to be full of rubbish. Last spring, '
          'several neighbours suggested turning it into a garden. At first, nobody '
          'knew who would water the plants during the working week. We made a '
          'simple schedule and shared the responsibility. Some seeds failed to grow, '
          'but we learned from the mistakes. The garden now gives us vegetables '
          'and a reason to talk to people we had rarely met before.',
      'How did the neighbours solve the problem of watering the plants?',
    ),
    'B2' => const LocalReadingLesson(
      'local-reading-b2-r2',
      'B2',
      'Repair before replacement',
      'A local repair group challenges the assumption that a broken object '
          'must be replaced. Volunteers help visitors identify faults and explain '
          'which repairs are practical. The benefits are not limited to reducing '
          'waste: people also gain confidence in understanding familiar tools. '
          'However, initial enthusiasm may fade unless responsibilities are shared. '
          'The organisers therefore built a resilient team with clear roles and '
          'regular training. Their experience suggests that a lasting community '
          'project needs both useful skills and a realistic plan.',
      'What makes this project more likely to continue?',
    ),
    'C1' => const LocalReadingLesson(
      'local-reading-c1-r1',
      'C1',
      'Measuring a useful service',
      'When a library evaluates its digital service, counting visits offers '
          'only a partial account of its value. A brief visit might indicate '
          'either efficient access or immediate frustration. Similarly, frequent '
          'use does not necessarily demonstrate that readers have found reliable '
          'information. A more defensible evaluation combines usage patterns with '
          'carefully framed feedback and accessible support. Even then, the findings '
          'remain dependent on who participates. Acknowledging these limits makes '
          'the evaluation more informative, rather than undermining its purpose.',
      'Why can the same usage measure support different interpretations?',
    ),
    'C2' => const LocalReadingLesson(
      'local-reading-c2-r1',
      'C2',
      'The convenience of certainty',
      'Public discussions often reward an appearance of certainty that the '
          'available evidence cannot sustain. This is not simply a failure of '
          'individual judgement; concise formats can privilege decisive statements '
          'over qualified explanations. Yet qualification need not collapse into '
          'indecision. An argument can distinguish what is established from what '
          'is plausible while still recommending action. The harder task is to '
          'make the grounds for revision explicit, so that changing a conclusion '
          'in response to better evidence is recognised as intellectual discipline '
          'rather than inconsistency.',
      'How does the writer reconcile uncertainty with a recommendation to act?',
    ),
    _ => throw ArgumentError.value(level, 'level', 'Unsupported reading level'),
  };
}

final class LocalReadingLesson {
  const LocalReadingLesson(
    this.id,
    this.level,
    this.title,
    this.text,
    this.reflection,
  );
  final String id;
  final String level;
  final String title;
  final String text;
  final String reflection;
}
