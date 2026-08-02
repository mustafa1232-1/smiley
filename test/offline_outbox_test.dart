import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smiley/core/offline_outbox.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('offline outbox stores and removes messages', () async {
    const outbox = SharedPreferencesOfflineOutbox();

    await outbox.enqueueMessage('hello');
    final messages = await outbox.messages();

    expect(messages, hasLength(1));
    expect(messages.single.body, 'hello');

    await outbox.removeMessage(messages.single.id);
    expect(await outbox.messages(), isEmpty);
  });

  test('offline outbox stores posts with assets', () async {
    const outbox = SharedPreferencesOfflineOutbox();

    await outbox.enqueuePost(body: 'memory', assetIds: ['asset']);
    final posts = await outbox.posts();

    expect(posts, hasLength(1));
    expect(posts.single.body, 'memory');
    expect(posts.single.assetIds, ['asset']);
  });
}
