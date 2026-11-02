@IsTest
private class de_dummy_Account_Research_ApexTest {
  @IsTest
  static void getResearchAreaOptions_returnsTwelve() {
    List<de_dummy_Account_Research_Apex.ResearchAreaOption> opts = de_dummy_Account_Research_Apex.getResearchAreaOptions();
    System.assertEquals(12, opts.size(), 'All research areas should be exposed');
    System.assertEquals('company_overview', opts[0].value);
  }

  @IsTest
  static void generateResearch_success_mockedLlm() {
    Account a = new Account(
      Name = 'Acme Test Corp',
      Industry = 'Technology',
      Website = 'https://acme.example',
      BillingCity = 'Austin',
      BillingCountry = 'US'
    );
    insert a;

    Test.startTest();
    de_dummy_Account_Research_Apex.ResearchResult r = de_dummy_Account_Research_Apex.generateResearch(
      a.Id,
      'company_overview'
    );
    Test.stopTest();

    System.assertEquals(true, r.success, r.errorMessage);
    System.assert(!String.isBlank(r.overviewHtml));
    System.assert(!String.isBlank(r.coachingBody));
    System.assert(r.sources != null && r.sources.size() >= 2);
  }

  @IsTest
  static void generateResearch_unknownArea() {
    Account a = new Account(Name = 'Solo');
    insert a;
    de_dummy_Account_Research_Apex.ResearchResult r = de_dummy_Account_Research_Apex.generateResearch(
      a.Id,
      'invalid_key'
    );
    System.assertEquals(false, r.success);
    System.assert(!String.isBlank(r.errorMessage));
  }

  @IsTest
  static void generateResearch_nullAccount() {
    de_dummy_Account_Research_Apex.ResearchResult r = de_dummy_Account_Research_Apex.generateResearch(
      null,
      'company_overview'
    );
    System.assertEquals(false, r.success);
  }
}
