@IsTest
private class de_Image_Capture_ServiceTest {
  private static final String TEST_IMAGE_BASE64 =
    EncodingUtil.base64Encode(Blob.valueOf('test-image'));

  @IsTest
  static void saveVisitingCardImage_withoutRecord_returnsContentDocumentId() {
    Test.startTest();
    Id docId = de_Image_Capture_Service.saveVisitingCardImage(
      TEST_IMAGE_BASE64,
      'card.png',
      'Test capture',
      null
    );
    Test.stopTest();
    System.assertNotEquals(null, docId);
    ContentDocument cd = [SELECT Id FROM ContentDocument WHERE Id = :docId LIMIT 1];
    System.assertEquals(docId, cd.Id);
  }

  @IsTest
  static void saveVisitingCardImage_withAccount_linksToRecord() {
    Account a = new Account(Name = 'ImgCap Test');
    insert a;

    Test.startTest();
    Id docId = de_Image_Capture_Service.saveVisitingCardImage(
      TEST_IMAGE_BASE64,
      'card.png',
      'On record',
      a.Id
    );
    Test.stopTest();
    System.assertNotEquals(null, docId);
    ContentDocumentLink[] links = [
      SELECT Id
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :a.Id AND ContentDocumentId = :docId
    ];
    System.assertEquals(1, links.size());
  }

  @IsTest
  static void searchAccountsByName_returnsMatches() {
    insert new List<Account>{
      new Account(Name = 'deImgCap Alpha Unique'),
      new Account(Name = 'deImgCap Beta Unique')
    };

    List<de_Image_Capture_Service.AccountPickOption> rows = de_Image_Capture_Service.searchAccountsByName(
      'deImgCap',
      10
    );
    System.assert(rows.size() >= 2, 'Expected at least two Accounts');
  }

  @IsTest
  static void searchAccountsByName_shortTerm_returnsEmpty() {
    System.assertEquals(
      0,
      de_Image_Capture_Service.searchAccountsByName('x', 10).size()
    );
  }

  @IsTest
  static void saveVisitingCardImage_blankBase64_throws() {
    Boolean threw = false;
    try {
      de_Image_Capture_Service.saveVisitingCardImage('', 'x.png', 't', null);
    } catch (AuraHandledException e) {
      threw = true;
    }
    System.assert(threw, 'Expected AuraHandledException');
  }
}
