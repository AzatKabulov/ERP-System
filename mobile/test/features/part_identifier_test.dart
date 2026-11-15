import 'package:erp_system/features/scanning/part_identifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'FUSO composite keeps the article and never treats the suffix as quantity',
    () {
      expect(identifyPart('MH044089  0001')?.article, 'MH044089');
      expect(identifyPart('ME996364')?.article, 'ME996364');
      expect(identifyPart('KYB 444083')?.brand, 'KYB');
      expect(identifyPart('8-97096777-0')?.article, '8-97096777-0');
      for (final raw in [
        '0007',
        '1950',
        'https://x.test',
        'advert\nME996364',
      ]) {
        expect(identifyPart(raw), isNull, reason: raw);
      }
    },
  );
  test(
    'OCR selects real articles and excludes engine families, standards and quantities',
    () {
      expect(
        partCandidates('MITSUBISHI FUSO\nTHERMO KIT\nME996364\nQTY: 1\n4D34'),
        ['MITSUBISHI FUSO ME996364'],
      );
      expect(
        partCandidates(
          'KYB Corporation\nSHOCK ABSORBER 1PC\n444083\nMade in Japan',
        ),
        contains('KYB 444083'),
      );
      expect(partCandidates('TAIHO\nTHRUST\n4D34\nT121A\nISO 9001:2015'), [
        'TAIHO T121A',
      ]);
      expect(
        partCandidates('SUPREME\nYCE 0926\n35 mm\nISO 9001:2015'),
        contains('SUPREME YCE0926'),
      );
    },
  );
  test(
    'OCR does not silently repair a visually similar but different article',
    () {
      expect(
        partCandidates('ME996364 ME99636A'),
        containsAll(['ME996364', 'ME99636A']),
      );
      expect(identifyPart('ME99636O')?.article, 'ME99636O');
    },
  );
}
