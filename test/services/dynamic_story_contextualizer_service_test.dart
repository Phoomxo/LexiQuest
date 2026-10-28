import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/dynamic_story_contextualizer_service.dart';

void main() {
  test('generateStory builds micro-story for template target word', () {
    final story = DynamicStoryContextualizerService.generateStory(
      'opportunity',
    );

    expect(story.targetWord, 'opportunity');
    expect(story.cefrLevel, 'B1');
    expect(story.storyTitle, 'The Golden Chance');
    expect(story.storyText, contains('opportunity'));
  });

  test('generateStory builds fallback story for unknown words', () {
    final story = DynamicStoryContextualizerService.generateStory('quantum');

    expect(story.targetWord, 'quantum');
    expect(story.storyText, contains('quantum'));
  });
}
