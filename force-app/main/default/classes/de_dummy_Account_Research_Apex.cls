/**
 * Account research generation for de_dummy_Account_Research LWC.
 * Uses Einstein / AI Platform Models API (same pattern as LLMMockedAction) to produce structured JSON.
 */
public with sharing class de_dummy_Account_Research_Apex {
  private static final String MODEL_NAME = 'llmgateway__OpenAIGPT4Omni';

  /** Combobox options (label + value for lightning-combobox). */
  public class ResearchAreaOption {
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String value { get; set; }
  }

  public class ResearchSourceItem {
    @AuraEnabled
    public String id { get; set; }
    @AuraEnabled
    public String title { get; set; }
    @AuraEnabled
    public String url { get; set; }
  }

  public class ResearchResult {
    @AuraEnabled
    public Boolean success { get; set; }
    @AuraEnabled
    public String errorMessage { get; set; }
    @AuraEnabled
    public String researchedMeta { get; set; }
    @AuraEnabled
    public String overviewHtml { get; set; }
    @AuraEnabled
    public String coachingSectionTitle { get; set; }
    @AuraEnabled
    public String coachingBody { get; set; }
    @AuraEnabled
    public List<ResearchSourceItem> sources { get; set; }
  }

  @AuraEnabled(cacheable=true)
  public static List<ResearchAreaOption> getResearchAreaOptions() {
    List<ResearchAreaOption> out = new List<ResearchAreaOption>();
    for (ResearchAreaDef def : AREA_DEFINITIONS) {
      ResearchAreaOption o = new ResearchAreaOption();
      o.label = def.label;
      o.value = def.apiValue;
      out.add(o);
    }
    return out;
  }

  /**
   * Runs research for the Account and selected area; calls the Models API (non-cacheable).
   */
  @AuraEnabled
  public static ResearchResult generateResearch(Id accountId, String researchAreaKey) {
    ResearchResult res = new ResearchResult();
    res.success = false;
    res.sources = new List<ResearchSourceItem>();

    if (accountId == null) {
      res.errorMessage = 'Open this component on an Account record.';
      return res;
    }
    if (accountId.getSobjectType() != Account.SObjectType) {
      res.errorMessage = 'Research is only available for Account records.';
      return res;
    }
    ResearchAreaDef area = findArea(researchAreaKey);
    if (area == null) {
      res.errorMessage = 'Unknown research area.';
      return res;
    }

    Account acc;
    try {
      acc = [
        SELECT Name, Industry, Website, Description, BillingCity, BillingCountry
        FROM Account
        WHERE Id = :accountId
        WITH USER_MODE
        LIMIT 1
      ];
    } catch (QueryException qe) {
      res.errorMessage = 'Could not load the Account. Check your access.';
      return res;
    }

    String queryContext =
      'Account Name: ' +
      safe(acc.Name) +
      '\nIndustry: ' +
      safe(acc.Industry) +
      '\nWebsite: ' +
      safe(acc.Website) +
      '\nLocation: ' +
      safe(acc.BillingCity) +
      ', ' +
      safe(acc.BillingCountry) +
      '\nDescription: ' +
      safe(acc.Description) +
      '\n\nResearch area: ' +
      area.label +
      '\nTypical sources to reflect in narrative and source list: ' +
      area.sourceHint;

    String sampleJson =
      '{\n' +
      '  "researchedMeta": "Researched 30 Apr 2026 at 2:15 pm by ' +
      UserInfo.getName() +
      '",\n' +
      '  "overviewHtml": "<p>Concise HTML overview with <strong>bold</strong> or <em>italic</em> where useful.</p>",\n' +
      '  "coachingSectionTitle": "Related insights",\n' +
      '  "coachingBody": "One or two paragraphs of complementary analysis, risks, or talking points for the seller.",\n' +
      '  "sources": [\n' +
      '    { "title": "Example Registry", "url": "https://example.org" }\n' +
      '  ]\n' +
      '}';

    String rawJson;
    try {
      rawJson = callLlmForJson(queryContext, sampleJson);
    } catch (AuraHandledException e) {
      res.errorMessage = e.getMessage();
      return res;
    } catch (Exception e) {
      res.errorMessage = 'Research failed: ' + e.getMessage();
      return res;
    }

    try {
      fillResultFromJson(res, rawJson);
      res.success = true;
    } catch (Exception e) {
      res.errorMessage = 'Could not parse model output: ' + e.getMessage();
      res.success = false;
    }
    return res;
  }

  private static void fillResultFromJson(ResearchResult res, String rawJson) {
    String cleaned = stripCodeFences(rawJson);
    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(cleaned);

    res.researchedMeta = stringVal(root.get('researchedMeta'));
    res.overviewHtml = stringVal(root.get('overviewHtml'));
    res.coachingSectionTitle = stringVal(root.get('coachingSectionTitle'));
    res.coachingBody = stringVal(root.get('coachingBody'));

    if (String.isBlank(res.coachingSectionTitle)) {
      res.coachingSectionTitle = 'Related insights';
    }

    List<ResearchSourceItem> srcs = new List<ResearchSourceItem>();
    Object srcNode = root.get('sources');
    if (srcNode instanceof List<Object>) {
      Integer i = 1;
      for (Object o : (List<Object>) srcNode) {
        if (!(o instanceof Map<String, Object>)) {
          continue;
        }
        Map<String, Object> m = (Map<String, Object>) o;
        ResearchSourceItem s = new ResearchSourceItem();
        s.id = String.valueOf(i++);
        s.title = stringVal(m.get('title'));
        s.url = stringVal(m.get('url'));
        if (String.isBlank(s.url)) {
          s.url = 'https://example.com';
        }
        if (!String.isBlank(s.title)) {
          srcs.add(s);
        }
      }
    }
    res.sources = srcs;
  }

  private static String stringVal(Object o) {
    return o == null ? '' : String.valueOf(o);
  }

  private static String safe(String s) {
    return String.isBlank(s) ? '(not provided)' : s.trim();
  }

  private static String stripCodeFences(String raw) {
    if (String.isBlank(raw)) {
      return '{}';
    }
    String s = raw.trim();
    if (s.startsWith('```')) {
      s = s.substringAfter('\n');
      if (s.startsWith('```')) {
        s = s.substring(3);
      }
      if (s.endsWith('```')) {
        s = s.substring(0, s.length() - 3);
      }
      s = s.trim();
    }
    return s;
  }

  private static ResearchAreaDef findArea(String key) {
    if (String.isBlank(key)) {
      return null;
    }
    for (ResearchAreaDef d : AREA_DEFINITIONS) {
      if (d.apiValue.equalsIgnoreCase(key)) {
        return d;
      }
    }
    return null;
  }

  private class ResearchAreaDef {
    String apiValue;
    String label;
    String sourceHint;
    ResearchAreaDef(String apiValue, String label, String sourceHint) {
      this.apiValue = apiValue;
      this.label = label;
      this.sourceHint = sourceHint;
    }
  }

  private static final List<ResearchAreaDef> AREA_DEFINITIONS = new List<ResearchAreaDef>{
    new ResearchAreaDef(
      'company_overview',
      'Company Overview',
      'Official website, D&B, Bloomberg, annual reports'
    ),
    new ResearchAreaDef(
      'ownership_beneficial',
      'Ownership & Beneficial Ownership',
      'Corporate registries, Orbis, D&B, OpenOwnership'
    ),
    new ResearchAreaDef(
      'leadership_key_individuals',
      'Leadership & Key Individuals',
      'Company website, LinkedIn, BoardEx, World-Check'
    ),
    new ResearchAreaDef(
      'legal_litigation',
      'Legal History & Litigation',
      'Court databases (PACER/eCourts), Westlaw, LexisNexis'
    ),
    new ResearchAreaDef(
      'regulatory_compliance',
      'Regulatory & Compliance Status',
      'SEC/FCA/SEBI portals, regulatory filings, enforcement databases'
    ),
    new ResearchAreaDef(
      'financial_health',
      'Financial Health & Risk Signals',
      'Financial filings, Bloomberg, Capital IQ, D&B, Moody\'s/S&P'
    ),
    new ResearchAreaDef(
      'reputation_media',
      'Reputation & Media Coverage',
      'Google News, Factiva, Reuters, Bloomberg, social media'
    ),
    new ResearchAreaDef(
      'sanctions_watchlists',
      'Sanctions & Watchlists',
      'OFAC, UN sanctions list, EU sanctions map, World-Check'
    ),
    new ResearchAreaDef(
      'contracts_commercial',
      'Contracts & Commercial Relationships',
      'SEC filings, press releases, company website, PitchBook'
    ),
    new ResearchAreaDef(
      'industry_market',
      'Industry & Market Context',
      'IBISWorld, Gartner, McKinsey, Statista, industry reports'
    ),
    new ResearchAreaDef(
      'data_privacy_cyber',
      'Data Privacy & Cyber Risk',
      'GDPR regulators, data breach databases, company privacy policies'
    ),
    new ResearchAreaDef(
      'engagement_legal_need',
      'Engagement Context / Legal Need',
      'CRM (Salesforce), intake notes, emails, deal/news announcements'
    )
  };

  /**
   * Same generation pattern as LLMMockedAction: Models API with JSON-shaped output.
   */
  private static String callLlmForJson(String query, String sampleResponse) {
    if (Test.isRunningTest()) {
      return mockJsonResponse();
    }

    aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
    request.modelName = MODEL_NAME;

    aiplatform.ModelsAPI_GenerationRequest requestBody = new aiplatform.ModelsAPI_GenerationRequest();
    request.body = requestBody;

    Date today = Date.today();
    String prompt =
      'You are a B2B account intelligence assistant. Generate realistic, well-structured research for sales and legal teams.\n\n' +
      'Context and inputs:\n' +
      query +
      '\n\n' +
      'Sample output shape (follow keys and HTML rules; replace ALL content with new material specific to the inputs above):\n' +
      sampleResponse +
      '\n\n' +
      'Rules:\n' +
      '- Output a single JSON object only (no markdown fences, no commentary).\n' +
      '- Keys required: researchedMeta, overviewHtml, coachingSectionTitle, coachingBody, sources.\n' +
      '- overviewHtml must be valid HTML for lightning-formatted-rich-text (use <p>, <strong>, <em>, <ul><li> sparingly).\n' +
      '- sources: array of 4–8 objects with "title" and "url" (https URLs; use recognizable domains where plausible).\n' +
      '- researchedMeta should read like: Researched <date> at <time> by ' +
      UserInfo.getName() +
      ' (use org-appropriate locale).\n' +
      '- If dates are in the future, use a reasonable date after ' +
      today +
      '.\n' +
      '- If dates are in the past, use a reasonable date before ' +
      today +
      '.\n' +
      '- Be distinct from the sample text; expand with concrete, coherent detail tied to the Account and research area.\n';

    requestBody.prompt = prompt;

    try {
      aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
      aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(request);
      if (
        response == null ||
        response.Code200 == null ||
        response.Code200.generation == null
      ) {
        throw new AuraHandledException('Empty response from the model.');
      }
      String text = response.Code200.generation.generatedText;
      if (String.isBlank(text)) {
        throw new AuraHandledException('Model returned no text.');
      }
      return text;
    } catch (aiplatform.ModelsAPI.createGenerations_ResponseException e) {
      throw new AuraHandledException(
        'Models API error: ' + e.getMessage()
      );
    }
  }

  @TestVisible
  private static String mockJsonResponse() {
    return '{' +
      '"researchedMeta": "Researched 30 Apr 2026 at 9:00 am by ' +
      UserInfo.getName() +
      '",' +
      '"overviewHtml": "<p><strong>Test overview</strong> for the Account.</p>",' +
      '"coachingSectionTitle": "Related insights",' +
      '"coachingBody": "Test coaching body with enough text to verify preview and expand behavior in the UI.",' +
      '"sources": [' +
      '{"title":"Example Source","url":"https://example.com"},' +
      '{"title":"Second Source","url":"https://example.org"}' +
      ']' +
      '}';
  }
}
