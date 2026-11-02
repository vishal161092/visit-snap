/**
 * de_CaseConflictService — v1, no User/Account junction.
 * Type1: more than one distinct Case owner among open matters that share any Account with
 * this matter’s parties (Case.AccountId and/or de_Adverse_Client__c) on either side of any Case.
 * Type2: cross-party: same two Accounts as (primary, adverse) or inverse, plus one-sided open matters.
 * Related-open-work rows: only other partners' cases, never a row where the Case owner is the viewer.
 * Class is without sharing so the UI can list other partners’ open work for the demo; restrict via
 * permission set to this Apex class in production.
 */
public without sharing class de_CaseConflictService {
  /**
   * Max scope matters fully evaluated in {@link #mergeFromOpenCaseIds}. Merge uses a fixed
   * small number of bulk SOQL queries (scope Cases, Accounts, one shared open-matter pool for
   * type1 + type2) then runs type1/type2 rules in memory per case — so this can be much
   * larger than the old per-Id {@link #getConflictForCase} loop without hitting SOQL 101.
   */
  private static final Integer MAX_CASE_IDS_PER_MERGE_TRANSACTION = 500;
  /**
   * Max rows when gathering open Case Ids for partner home (before merge sorts and caps).
   * Prevents unbounded query size when a user owns a very large number of open cases.
   */
  private static final Integer MAX_OWNED_OPEN_CASES_FOR_PARTNER_LIST = 2000;
  /**
   * Max open Cases returned for account / contact scope lists (newest first). Merge then
   * takes the top {@link #MAX_CASE_IDS_PER_MERGE_TRANSACTION} by LastModifiedDate.
   */
  private static final Integer MAX_SCOPE_CASE_IDS_FROM_QUERY = 2000;
  /**
   * Row cap on the type2 cross-party candidate pool (Account or adverse in the scope party set).
   * If the org exceeds this, append a truncation note on the merge result.
   */
  private static final Integer MAX_TYPE2_POOL_ROWS = 20000;

  @AuraEnabled
  public static de_ConflictResult getConflictForCase(Id caseId) {
    de_ConflictResult res = new de_ConflictResult();
    res.hasConflict = false;
    res.conflictType = 'NONE';
    res.message = '';
    res.rows = new List<de_ConflictRow>();

    if (caseId == null) {
      res.conflictType = 'ERROR';
      res.message = 'No case was specified.';
      return res;
    }

    List<Case> baseRows = [
      SELECT
        Id,
        AccountId,
        de_Adverse_Client__c,
        OwnerId,
        IsClosed,
        CaseNumber,
        Subject
      FROM Case
      WHERE Id = :caseId
      LIMIT 1
    ];

    if (baseRows.isEmpty()) {
      res.conflictType = 'ERROR';
      res.message = 'Case not found.';
      return res;
    }
    Case c = baseRows[0];

    if (c.IsClosed) {
      res.message = 'This case is closed. Conflict view applies to open work only.';
      return res;
    }

    Set<Id> toName = new Set<Id>();
    if (c.AccountId != null) {
      toName.add(c.AccountId);
    }
    if (c.de_Adverse_Client__c != null) {
      toName.add(c.de_Adverse_Client__c);
    }
    Map<Id, Account> byId = toName.isEmpty()
      ? new Map<Id, Account>()
      : new Map<Id, Account>([SELECT Id, Name FROM Account WHERE Id IN :toName]);

    List<de_ConflictRow> t1 = new List<de_ConflictRow>();
    List<de_ConflictRow> t2 = new List<de_ConflictRow>();
    Boolean hit1 = false;
    Boolean hit2 = false;

    Set<Id> anchorSet = type1AnchorIds(c);
    List<Case> partyPool = anchorSet.isEmpty()
      ? new List<Case>()
      : queryType2Pool(anchorSet);
    if (!anchorSet.isEmpty()) {
      hit1 = type1EvaluateWithOpenList(
        c,
        byId,
        partyPool,
        t1
      );
    }
    hit2 = type2EvaluateWithPool(
      c,
      byId,
      t2,
      partyPool
    );

    if (hit1 && hit2) {
      res.hasConflict = true;
      res.conflictType = 'BOTH';
      res.message = msg1(
        c,
        byId,
        t1
      ) + ' ' + msg2(
        c,
        byId,
        t2
      );
    } else if (hit1) {
      res.hasConflict = true;
      res.conflictType = 'TYPE1';
      res.message = msg1(
        c,
        byId,
        t1
      );
    } else if (hit2) {
      res.hasConflict = true;
      res.conflictType = 'TYPE2';
      res.message = msg2(
        c,
        byId,
        t2
      );
    } else {
      res.message = 'No conflict detected for open work under the current de rules.';
    }

    for (de_ConflictRow r : t1) {
      res.rows.add(r);
    }
    for (de_ConflictRow r : t2) {
      if (!rowPresentWithKey(
        res.rows,
        r
      )) {
        res.rows.add(r);
      }
    }
    reconcileResultForViewer(
      res
    );
    return res;
  }

  /**
   * Home / Partner: all open cases owned by the running user (the lawyer partner) — no Id
   * passed from the LWC. Same Type1/Type2 merge as other scopes.
   */
  @AuraEnabled
  public static de_ConflictResult getConflictForCurrentPartner() {
    return mergeFromOpenCaseIds(
      caseIdsForPartnerUser(
        UserInfo.getUserId()
      ),
      'No open cases are assigned to you as owner. Nothing to check in partner scope.',
      'No business conflict in partner scope (your open work) under the de rules.',
      'de Partner (your open matters)'
    );
  }

  /**
   * Account / client (company): same as before — open cases where this Account is primary or
   * adverse.
   */
  @AuraEnabled
  public static de_ConflictResult getConflictForAccount(Id accountId) {
    if (accountId == null) {
      de_ConflictResult e = new de_ConflictResult();
      e.conflictType = 'ERROR';
      e.message = 'No account was specified.';
      return e;
    }
    List<Id> ids = new List<Id>();
    Integer scopeLim = MAX_SCOPE_CASE_IDS_FROM_QUERY;
    for (Case c : [
      SELECT Id
      FROM Case
      WHERE
        IsClosed = FALSE
        AND (AccountId = :accountId OR de_Adverse_Client__c = :accountId)
      ORDER BY LastModifiedDate DESC, CreatedDate DESC
      LIMIT :scopeLim
    ]) {
      ids.add(c.Id);
    }
    return mergeFromOpenCaseIds(
      ids,
      'No open cases linked to this account (as primary or de adverse) to check.',
      'No conflict detected for open work under the de rules in account scope.',
      'de Account scope'
    );
  }

  /**
   * Contact (POC): open cases for this person as the Case contact, and open cases for the
   * same client company when the Contact’s Account is set.
   */
  @AuraEnabled
  public static de_ConflictResult getConflictForContact(Id contactId) {
    if (contactId == null) {
      de_ConflictResult e = new de_ConflictResult();
      e.conflictType = 'ERROR';
      e.message = 'No contact was specified.';
      return e;
    }
    List<Contact> con = [SELECT Id, AccountId FROM Contact WHERE Id = :contactId LIMIT 1];
    if (con.isEmpty()) {
      de_ConflictResult e2 = new de_ConflictResult();
      e2.conflictType = 'ERROR';
      e2.message = 'Contact not found or not visible.';
      return e2;
    }
    Id accId = con[0].AccountId;
    List<Id> ids = new List<Id>();
    Integer scopeLim2 = MAX_SCOPE_CASE_IDS_FROM_QUERY;
    if (accId != null) {
      for (Case c2 : [
        SELECT Id
        FROM Case
        WHERE
          IsClosed = FALSE
          AND (ContactId = :contactId OR AccountId = :accId)
        ORDER BY LastModifiedDate DESC, CreatedDate DESC
        LIMIT :scopeLim2
      ]) {
        ids.add(c2.Id);
      }
    } else {
      for (Case c2 : [
        SELECT Id
        FROM Case
        WHERE
          IsClosed = FALSE
          AND ContactId = :contactId
        ORDER BY LastModifiedDate DESC, CreatedDate DESC
        LIMIT :scopeLim2
      ]) {
        ids.add(c2.Id);
      }
    }
    return mergeFromOpenCaseIds(
      ids,
      'No open cases for this person (or their client) to check in POC scope.',
      'No conflict detected in POC / client open matter scope.',
      'de Contact / client matter scope'
    );
  }

  private static List<Id> caseIdsForPartnerUser(Id userId) {
    List<Id> u = new List<Id>();
    Integer gatherLim = MAX_OWNED_OPEN_CASES_FOR_PARTNER_LIST;
    for (Case c0 : [
      SELECT Id
      FROM Case
      WHERE
        IsClosed = FALSE
        AND OwnerId = :userId
      ORDER BY LastModifiedDate DESC, CreatedDate DESC
      LIMIT :gatherLim
    ]) {
      u.add(c0.Id);
    }
    return u;
  }

  /**
   * Resolves Ids to open Cases, orders by {@code LastModifiedDate} descending then
   * {@code CreatedDate} descending (tie-break), evaluates at most
   * {@link #MAX_CASE_IDS_PER_MERGE_TRANSACTION} matters using bulk Case/Account queries and
   * the same type1/type2 rules as {@link #getConflictForCase} (in-memory over shared pools).
   */
  private static de_ConflictResult mergeFromOpenCaseIds(
    List<Id> caseIds,
    String emptyMessage,
    String noConflictMessage,
    String conflictMessagePrefix
  ) {
    de_ConflictResult res = new de_ConflictResult();
    res.hasConflict = false;
    res.conflictType = 'NONE';
    res.message = '';
    res.rows = new List<de_ConflictRow>();
    if (caseIds == null || caseIds.isEmpty()) {
      res.message = emptyMessage;
      return res;
    }

    Set<Id> idSet = new Set<Id>();
    for (Id cid : caseIds) {
      if (cid != null) {
        idSet.add(cid);
      }
    }
    if (idSet.isEmpty()) {
      res.message = emptyMessage;
      return res;
    }

    Integer lim = MAX_CASE_IDS_PER_MERGE_TRANSACTION;
    List<Case> scopeCases = [
      SELECT
        Id,
        AccountId,
        de_Adverse_Client__c,
        OwnerId,
        IsClosed,
        CaseNumber,
        Subject
      FROM Case
      WHERE
        Id IN :idSet
      ORDER BY LastModifiedDate DESC, CreatedDate DESC
      LIMIT :lim
    ];
    if (scopeCases.isEmpty()) {
      res.message = emptyMessage;
      return res;
    }

    Boolean truncated = idSet.size() > lim;

    Set<Id> partyIds = new Set<Id>();
    for (Case c0 : scopeCases) {
      if (c0.IsClosed) {
        continue;
      }
      if (c0.AccountId != null) {
        partyIds.add(c0.AccountId);
      }
      if (c0.de_Adverse_Client__c != null) {
        partyIds.add(c0.de_Adverse_Client__c);
      }
    }

    Map<Id, Account> accountMap = partyIds.isEmpty()
      ? new Map<Id, Account>()
      : new Map<Id, Account>([
          SELECT Id, Name
          FROM Account
          WHERE Id IN :partyIds
        ]);

    List<Case> type2Pool = partyIds.isEmpty()
      ? new List<Case>()
      : queryType2Pool(partyIds);
    Boolean type2PoolCapped = !partyIds.isEmpty()
      && type2Pool.size() >= MAX_TYPE2_POOL_ROWS;

    Boolean anyT1 = false;
    Boolean anyT2 = false;
    Map<String, de_ConflictRow> rowByKey = new Map<String, de_ConflictRow>();
    String firstMsg = '';
    for (Case c : scopeCases) {
      if (c.IsClosed) {
        continue;
      }
      List<de_ConflictRow> t1 = new List<de_ConflictRow>();
      List<de_ConflictRow> t2 = new List<de_ConflictRow>();
      Boolean hit1 = false;
      Boolean hit2 = false;
      Set<Id> t1Anchors = type1AnchorIds(c);
      if (!t1Anchors.isEmpty()) {
        hit1 = type1EvaluateWithOpenList(
          c,
          accountMap,
          type2Pool,
          t1
        );
      }
      hit2 = type2EvaluateWithPool(
        c,
        accountMap,
        t2,
        type2Pool
      );

      if (hit1 || hit2) {
        res.hasConflict = true;
        if (hit1) {
          anyT1 = true;
        }
        if (hit2) {
          anyT2 = true;
        }
        String m = '';
        if (hit1 && hit2) {
          m = msg1(
            c,
            accountMap,
            t1
          ) + ' ' + msg2(
            c,
            accountMap,
            t2
          );
        } else if (hit1) {
          m = msg1(
            c,
            accountMap,
            t1
          );
        } else {
          m = msg2(
            c,
            accountMap,
            t2
          );
        }
        if (String.isNotBlank(m) && firstMsg == '') {
          firstMsg = m;
        }
      }
      for (de_ConflictRow row : t1) {
        if (row == null) {
          continue;
        }
        String rk = rowDedupeKey(row);
        if (!rowByKey.containsKey(
          rk
        )) {
          rowByKey.put(
            rk,
            row
          );
        }
      }
      for (de_ConflictRow row : t2) {
        if (row == null) {
          continue;
        }
        String rk = rowDedupeKey(row);
        if (!rowByKey.containsKey(
          rk
        )) {
          rowByKey.put(
            rk,
            row
          );
        }
      }
    }
    for (de_ConflictRow r0 : rowByKey.values()) {
      res.rows.add(
        r0
      );
    }
    reconcileResultForViewer(
      res
    );
    if (res.hasConflict) {
      if (anyT1 && anyT2) {
        res.conflictType = 'BOTH';
      } else if (anyT1) {
        res.conflictType = 'TYPE1';
      } else {
        res.conflictType = 'TYPE2';
      }
      res.message = '**' + conflictMessagePrefix
        + '** — ' + (firstMsg != null ? firstMsg
        : 'A conflict was found in at least one open matter in this scope.');
    } else if (res.conflictType == 'ERROR') {
      // keep
    } else {
      res.message = noConflictMessage;
    }

    if (truncated && res.conflictType != 'ERROR') {
      String suffix = ' Partial check: only the '
        + String.valueOf(
          MAX_CASE_IDS_PER_MERGE_TRANSACTION
        )
        + ' most recently modified matters in this scope were fully evaluated (batch scope limit).';
      res.message = (res.message == null ? '' : res.message) + suffix;
    }
    if (type2PoolCapped && res.conflictType != 'ERROR') {
      String capNote = ' Cross-party search was limited to '
        + String.valueOf(MAX_TYPE2_POOL_ROWS)
        + ' open matters tied to parties in this scope; some Type 2 matches could be missing if the org exceeds that volume.';
      res.message = (res.message == null ? '' : res.message) + capNote;
    }
    return res;
  }

  /**
   * The UI lists only other partners: drop rows for cases the viewer owns.
   * If nothing remains, the result is no conflict (no empty banner and list).
   */
  private static void reconcileResultForViewer(
    de_ConflictResult res
  ) {
    if (res == null) {
      return;
    }
    if (res.conflictType == 'ERROR') {
      return;
    }
    if (res.hasConflict
      == true
      && (res.rows == null
      || res.rows.isEmpty())) {
      res.hasConflict = false;
      res.conflictType = 'NONE';
      res.message = 'No conflict detected for open work under the current de rules.';
    }
  }

  private static Boolean otherPartnerCase(
    Id caseOwnerId
  ) {
    if (caseOwnerId == null) {
      return false;
    }
    return caseOwnerId
      != UserInfo.getUserId();
  }

  /**
   * Stable key so Type1 and Type2 rows for the same other Case (same forCaseId + caseId) are
   * both kept; only true duplicates (same kind + same endpoints) collapse.
   */
  private static String rowDedupeKey(
    de_ConflictRow r
  ) {
    if (r == null) {
      return '';
    }
    String kind = 'T1';
    if (r.typeLabel != null) {
      String tl = r.typeLabel.toLowerCase();
      if (tl.contains('cross-party') || tl.contains('type 2')) {
        kind = 'T2';
      }
    }
    String fid = r.forCaseId == null
      ? 'null'
      : String.valueOf(
        r.forCaseId
      );
    String cid = r.caseId == null
      ? 'null'
      : String.valueOf(
        r.caseId
      );
    return kind + '::' + fid + '::' + cid;
  }

  private static Boolean rowPresentWithKey(
    List<de_ConflictRow> have,
    de_ConflictRow r
  ) {
    if (r == null || have == null) {
      return false;
    }
    String k = rowDedupeKey(r);
    for (de_ConflictRow x : have) {
      if (x != null && rowDedupeKey(x) == k) {
        return true;
      }
    }
    return false;
  }

  /**
   * Party accounts on this matter used for Type1 “same client / different owner” overlap.
   */
  private static Set<Id> type1AnchorIds(
    Case c
  ) {
    Set<Id> s = new Set<Id>();
    if (c == null) {
      return s;
    }
    if (c.AccountId != null) {
      s.add(c.AccountId);
    }
    if (c.de_Adverse_Client__c != null) {
      s.add(c.de_Adverse_Client__c);
    }
    return s;
  }

  private static Boolean caseTouchesPartySet(
    Case o,
    Set<Id> partyIds
  ) {
    if (o == null || partyIds == null || partyIds.isEmpty()) {
      return false;
    }
    if (o.AccountId != null && partyIds.contains(o.AccountId)) {
      return true;
    }
    if (o.de_Adverse_Client__c != null && partyIds.contains(o.de_Adverse_Client__c)) {
      return true;
    }
    return false;
  }

  /**
   * Type1 over a list of open cases (e.g. merge party pool): keeps those that share any party
   * Account with this matter’s anchors.
   */
  private static Boolean type1EvaluateWithOpenList(
    Case c,
    Map<Id, Account> byId,
    List<Case> allOpen,
    List<de_ConflictRow> outRows
  ) {
    Set<Id> anchors = type1AnchorIds(c);
    if (anchors.isEmpty() || allOpen == null || allOpen.isEmpty()) {
      return false;
    }
    List<Case> related = new List<Case>();
    for (Case o : allOpen) {
      if (caseTouchesPartySet(
        o,
        anchors
      )) {
        related.add(o);
      }
    }
    if (related.isEmpty()) {
      return false;
    }
    Set<Id> owners = new Set<Id>();
    for (Case o : related) {
      owners.add(o.OwnerId);
    }
    if (owners.size() <= 1) {
      return false;
    }
    Id labelAcct = c.AccountId != null
      ? c.AccountId
      : c.de_Adverse_Client__c;
    String an = labelAcct != null && byId != null && byId.containsKey(labelAcct)
      ? byId.get(labelAcct).Name
      : 'This client';
    for (Case o : related) {
      if (o.Id == c.Id) {
        continue;
      }
      if (!otherPartnerCase(
        o.OwnerId
      )) {
        continue;
      }
      de_ConflictRow r = new de_ConflictRow();
      r.caseId = o.Id;
      r.caseNumber = o.CaseNumber;
      r.subject = o.Subject;
      r.forCaseId = c.Id;
      r.forCaseNumber = c.CaseNumber;
      r.forCaseSubject = c.Subject;
      r.ownerName = o.Owner == null ? '' : o.Owner.Name;
      r.otherPartnerName = r.ownerName;
      r.clientName = an;
      r.typeLabel = 'Same client (Type 1)';
      {
        String pn = o.Owner == null ? '—' : o.Owner.Name;
        r.detail = 'Open case **' + (o.CaseNumber != null ? o.CaseNumber
          : '—') + '** for ' + an
          + ' is owned by **' + pn
          + '** (other partner; different case owner in open work for this client).';
      }
      outRows.add(r);
    }
    return !outRows.isEmpty();
  }

  /**
   * Comma-joined, bolded names for the conflict rows (other partners).
   */
  private static String uniquePartnerNames(
    List<de_ConflictRow> rows
  ) {
    if (rows == null || rows.isEmpty()) {
      return '';
    }
    Set<String> s = new Set<String>();
    for (de_ConflictRow r : rows) {
      if (r == null) {
        continue;
      }
      if (String.isNotBlank(
        r.ownerName
      )) {
        s.add(
          r.ownerName.trim()
        );
      }
    }
    if (s.isEmpty()) {
      return '';
    }
    List<String> l = new List<String>(
      s
    );
    l.sort();
    if (l.size() == 1) {
      return '**' + l[0] + '**';
    }
    if (l.size() == 2) {
      return '**' + l[0] + '** and **' + l[1] + '**';
    }
    String all = '**' + l[0] + '**';
    for (Integer i = 1; i < l.size() - 1; i++) {
      all += ', **' + l[i] + '**';
    }
    all += ', and **' + l[l.size() - 1] + '**';
    return all;
  }

  private static String msg1(
    Case c,
    Map<Id, Account> byId,
    List<de_ConflictRow> t1
  ) {
    String n = byId.containsKey(
      c.AccountId
    ) ? byId.get(
      c.AccountId
    ).Name : 'this client';
    String who = uniquePartnerNames(
      t1
    );
    String withWho = String.isNotBlank(
      who
    )
      ? 'Coordinate with ' + who + ' before you proceed.'
      : 'Coordinate with the other case owner(s) before you proceed.';
    return '**Type 1 —** Another open case for ' + n
      + ' is or was assigned to a different partner. ' + withWho;
  }

  private static String msg2(
    Case c,
    Map<Id, Account> byId,
    List<de_ConflictRow> t2
  ) {
    String who = uniquePartnerNames(
      t2
    );
    String withWho = String.isNotBlank(
      who
    )
      ? 'Check with ' + who + ' before you proceed.'
      : 'Check with the other case owner before you proceed.';

    if (c.AccountId == null) {
      return '**Type 2 —** A related open matter for the same two organizations is owned by a different partner. '
        + withWho;
    }
    String p = byId.get(
      c.AccountId
    ) != null ? byId.get(
      c.AccountId
    ).Name : 'this client';
    if (c.de_Adverse_Client__c != null) {
      String a = byId.get(
        c.de_Adverse_Client__c
      ) != null ? byId.get(
        c.de_Adverse_Client__c
      ).Name
        : 'adverse';
      return '**Type 2 —** A cross-party or one-sided open matter for '
        + p
        + ' and/or '
        + a
        + ' exists with a different case owner. ' + withWho;
    }
    return '**Type 2 —** Another open matter links ' + p
      + ' to a named adverse client, or the reverse (one-sided on this case). ' + withWho;
  }

  private static List<Case> queryType2Pool(
    Set<Id> parties
  ) {
    if (parties == null || parties.isEmpty()) {
      return new List<Case>();
    }
    return [
      SELECT
        Id,
        CaseNumber,
        Subject,
        AccountId,
        de_Adverse_Client__c,
        OwnerId,
        Owner.Name
      FROM Case
      WHERE
        IsClosed = FALSE
        AND (
          AccountId IN :parties
          OR de_Adverse_Client__c IN :parties
        )
      LIMIT :MAX_TYPE2_POOL_ROWS
    ];
  }

  /**
   * Type2 rules over a preloaded pool (must include every Case the legacy per-branch SOQL
   * could return for parties = primary + adverse of {@code c}).
   */
  private static Boolean type2EvaluateWithPool(
    Case c,
    Map<Id, Account> byId,
    List<de_ConflictRow> out,
    List<Case> pool
  ) {
    if (c.AccountId == null || pool == null || pool.isEmpty()) {
      return false;
    }
    Id p = c.AccountId;
    Id a = c.de_Adverse_Client__c;
    Boolean type2Hit = false;

    if (a != null) {
      for (Case o : pool) {
        if (o.Id == c.Id) {
          continue;
        }
        if (!(
          (
            o.AccountId == p
            && o.de_Adverse_Client__c == a
          )
          || (
            o.AccountId == a
            && o.de_Adverse_Client__c == p
          )
        )) {
          continue;
        }
        if (o.OwnerId == c.OwnerId) {
          continue;
        }
        if (addRow(
            c,
            byId,
            o,
            out,
            'Full pair: primary and adverse both match the same two companies (in either order).'
            )) { type2Hit = true; }
      }
      for (Case o : pool) {
        if (o.Id == c.Id) {
          continue;
        }
        if (!(o.AccountId == p && o.de_Adverse_Client__c == null)) {
          continue;
        }
        if (o.OwnerId == c.OwnerId) {
          continue;
        }
        if (addRow(
            c,
            byId,
            o,
            out,
            'One-sided: the other case has the same primary client and no adverse (overlaps a full-pair matter).'
            )) { type2Hit = true; }
      }
      for (Case o : pool) {
        if (o.Id == c.Id) {
          continue;
        }
        if (!(o.AccountId == a && o.de_Adverse_Client__c == null)) {
          continue;
        }
        if (o.OwnerId == c.OwnerId) {
          continue;
        }
        if (addRow(
            c,
            byId,
            o,
            out,
            'One-sided: the other case is adverse-as-primary with no second party, overlapping a full-pair matter.'
            )) { type2Hit = true; }
      }
    } else {
      for (Case o : pool) {
        if (o.Id == c.Id) {
          continue;
        }
        if (!(o.AccountId == p && o.de_Adverse_Client__c != null)) {
          continue;
        }
        if (o.OwnerId == c.OwnerId) {
          continue;
        }
        if (addRow(
            c,
            byId,
            o,
            out,
            'This case is primary-only; another open case lists an adverse for the same client.'
            )) { type2Hit = true; }
      }
      for (Case o : pool) {
        if (o.Id == c.Id) {
          continue;
        }
        if (!(o.de_Adverse_Client__c == p && o.AccountId != p)) {
          continue;
        }
        if (o.OwnerId == c.OwnerId) {
          continue;
        }
        if (addRow(
            c,
            byId,
            o,
            out,
            'Another case lists this client in the adverse role (cross-role overlap).'
            )) { type2Hit = true; }
      }
    }
    return type2Hit;
  }

  private static String labelPrimaryClient(
    Case forCase,
    Map<Id, Account> byId
  ) {
    if (forCase == null || forCase.AccountId == null) {
      return '—';
    }
    if (byId != null
      && byId.containsKey(
        forCase.AccountId
      )) {
      return byId.get(
        forCase.AccountId
      ).Name;
    }
    return 'This client';
  }

  private static Boolean addRow(
    Case forCase,
    Map<Id, Account> byId,
    Case o,
    List<de_ConflictRow> out,
    String detail
  ) {
    if (!otherPartnerCase(
      o.OwnerId
    )) {
      return false;
    }
    for (de_ConflictRow x : out) {
      if (x.caseId == o.Id) {
        return false;
      }
    }
    de_ConflictRow r = new de_ConflictRow();
    r.caseId = o.Id;
    r.caseNumber = o.CaseNumber;
    r.subject = o.Subject;
    r.forCaseId = forCase.Id;
    r.forCaseNumber = forCase.CaseNumber;
    r.forCaseSubject = forCase.Subject;
    r.ownerName = o.Owner == null ? '' : o.Owner.Name;
    r.otherPartnerName = r.ownerName;
    r.clientName = labelPrimaryClient(
      forCase,
      byId
    );
    r.typeLabel = 'Cross-party (Type 2)';
    {
      String pn = o.Owner == null ? '—' : o.Owner.Name;
      r.detail = detail
        + ' **Other partner:** **' + pn
        + '**.';
    }
    out.add(r);
    return true;
  }

  public class de_ConflictResult {
    @AuraEnabled
    public Boolean hasConflict;
    @AuraEnabled
    public String conflictType;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<de_ConflictRow> rows;
  }

  public class de_ConflictRow {
    @AuraEnabled
    public Id caseId;
    @AuraEnabled
    public String caseNumber;
    @AuraEnabled
    public String subject;
    /**
     * The open matter (viewer’s / scope case) the conflict was evaluated from — not the other
     * partner’s case listed in caseId.
     */
    @AuraEnabled
    public Id forCaseId;
    @AuraEnabled
    public String forCaseNumber;
    @AuraEnabled
    public String forCaseSubject;
    /**
     * Primary (Account) client name for the matter this row was evaluated from.
     */
    @AuraEnabled
    public String clientName;
    @AuraEnabled
    public String ownerName;
    @AuraEnabled
    public String otherPartnerName;
    @AuraEnabled
    public String detail;
    @AuraEnabled
    public String typeLabel;
  }
}
