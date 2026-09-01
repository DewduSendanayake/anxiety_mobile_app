import 'package:anxiety_mobile_app/models/demographic_model_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes the known supported model payload exactly', () {
    final input = DemographicModelInput.fromProfile(
      age: 22,
      genderLabel: 'Female',
      educationLabel: "Bachelor's degree",
      smokingLabel: 'Current smoker (cumulative smoking >10 packs)',
      drinkingLabel: 'Current regular drinker (more than once a week)',
    );

    expect(input.isComplete, isTrue);
    expect(input.toJson(), {
      'age': 22,
      'gender': 'female',
      'edu': "bachelor's degree",
      'smoke': 'current smoker (cumulative smoking >10 packs)',
      'drink': 'current regular drinker (more than once a week)',
    });
  });

  test('maps every supported trained category without changing punctuation', () {
    expect(
      DemographicModelInput.genderWireByLabel.values,
      containsAll(<String>['female', 'male']),
    );
    expect(
      DemographicModelInput.educationWireByLabel.values,
      containsAll(<String>[
        'associate degree',
        "bachelor's degree",
        "master's degree",
        'doctorate degree',
      ]),
    );
    expect(
      DemographicModelInput.smokingWireByLabel.values,
      containsAll(<String>[
        'never smokes',
        'occasional smoker (cumulative smoking <10 packs)',
        'former smoker (cumulative smoking >10 packs), but not in the past year',
        'current smoker (cumulative smoking >10 packs)',
      ]),
    );
    expect(
      DemographicModelInput.drinkingWireByLabel.values,
      containsAll(<String>[
        'never drinks',
        'drinks occasionally (less than once a week)',
        'drank in the past (more than once a week), but not in the past year',
        'current regular drinker (more than once a week)',
      ]),
    );
  });

  test('unsupported inclusive profile values are omitted rather than coerced', () {
    final input = DemographicModelInput.fromProfile(
      age: 22,
      genderLabel: 'Non-binary',
      educationLabel: 'A/L',
      smokingLabel: 'Prefer not to say',
      drinkingLabel: 'Prefer not to say',
    );

    expect(input.isComplete, isFalse);
    expect(input.toJson(), {'age': 22});
  });

  test('age outside the model range is omitted', () {
    final input = DemographicModelInput.fromProfile(
      age: 66,
      genderLabel: 'Female',
      educationLabel: "Bachelor's degree",
      smokingLabel: 'Never smokes',
      drinkingLabel: 'Never drinks',
    );

    expect(input.isComplete, isFalse);
    expect(input.toJson(), isNot(contains('age')));
  });

  test('controlled lifestyle choices include a non-model abstention', () {
    expect(
      DemographicModelInput.smokingChoices.last,
      'Prefer not to say',
    );
    expect(
      DemographicModelInput.drinkingChoices.last,
      'Prefer not to say',
    );
  });
}
