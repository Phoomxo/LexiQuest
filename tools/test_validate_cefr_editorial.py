import unittest
from validate_cefr_editorial import validate, validate_senses

class EditorialAuditTest(unittest.TestCase):
    def setUp(self):
        self.source=[{'id':'cefrj15:book','word':'book','cefrLevel':'A1','meanings':['หนังสือ']}]
        self.entry={'id':'cefrj15:book','senseKey':'primary-v1','sourceMeaningIndex':0,
         'meaning':'หนังสือ','example':'This book is about animals.','translation':'หนังสือเล่มนี้เกี่ยวกับสัตว์',
         'reviewNote':'book เป็นคำนามเอกพจน์','status':'ai-reviewed'}
    def test_valid_structure_is_not_language_certification(self):
        result=validate(self.source,[self.entry])
        self.assertEqual(result['coverage'],1)
        self.assertFalse(result['languageQualityCertifiedByThisCheck'])
    def test_missing_duplicate_and_mismatched_forms_fail(self):
        for entries in [[],[self.entry,self.entry],[dict(self.entry,example='These books are about animals.')],
                        [dict(self.entry,sourceMeaningIndex=5)],[dict(self.entry,status='certified')]]:
            with self.assertRaises(ValueError):validate(self.source,entries)

    def test_all_levels_are_covered_and_sense_review_partitions_original(self):
        source=[dict(self.source[0],cefrLevel='C2',meanings=['หนังสือ','จอง'])]
        self.assertEqual(validate(source,[self.entry])['coverage'],1)
        review={'id':'cefrj15:book','acceptedSourceMeaningIndices':[0],
                'excludedSourceMeanings':[{'index':1,'reason':'Verb sense mismatches this noun entry.'}],
                'status':'ai-reviewed','reviewNote':'Noun alternatives checked individually.'}
        self.assertEqual(validate_senses(source,[review])['sourceMeaningCount'],2)
        for broken in [dict(review,acceptedSourceMeaningIndices=[0,1]),
                       dict(review,excludedSourceMeanings=[]),
                       dict(review,reviewNote='bad\u0000note'),
                       dict(review,excludedSourceMeanings=[{'index':1,'reason':'bad\nreason'}]),
                       dict(review,status='certified')]:
            with self.assertRaises(ValueError):validate_senses(source,[broken])

if __name__=='__main__':unittest.main()
