import 'package:flutter_test/flutter_test.dart';
import 'package:krishisathi/core/models/app_models.dart';
import 'package:krishisathi/features/saathi/data/chat_scope_policy.dart';

void main() {
  test('general chat connected to a plot remains visible on that plot', () {
    const chat = ChatThreadModel(
      id: 'chat-1',
      title: 'Connected agronomy question',
      scope: 'general',
      messages: [],
      effectiveFarmId: 'farm-1',
      effectivePlotId: 'plot-1',
    );

    expect(
      ChatScopePolicy.belongsToPlot(chat, 'plot-1', diagnosisIds: const {}),
      isTrue,
    );
    expect(
      ChatScopePolicy.belongsToPlot(chat, 'plot-2', diagnosisIds: const {}),
      isFalse,
    );
  });

  test('scan chat follows its diagnosis into the plot', () {
    const chat = ChatThreadModel(
      id: 'chat-2',
      title: 'Leaf result',
      scope: 'scan',
      diagnosisCaseId: 'case-1',
      messages: [],
    );

    expect(
      ChatScopePolicy.belongsToPlot(
        chat,
        'plot-1',
        diagnosisIds: const {'case-1'},
      ),
      isTrue,
    );
  });
}
