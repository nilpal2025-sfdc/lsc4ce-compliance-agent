(() => {
  const LOG_PREFIX = '[visitCustomScript]';

  const CONFIG = {
    TARGET_FIELDS: ['NextProviderVisitObjective', 'PreProviderVisitNotes'],
    COMPLIANCE_RULE_OBJECT: 'Compliance_Rule__c',
    MIN_TEXT_LENGTH: 5,
  };

  let isWebPlatform = false;

  function log(msg) {
    console.log(LOG_PREFIX + ' ' + msg);
  }

  function logError(msg) {
    console.error(LOG_PREFIX + ' ' + msg);
  }

  log('Script loaded at ' + new Date().toISOString());
  log('CONFIG: ' + JSON.stringify(CONFIG));

  function getActionName(env) {
    try {
      log('getActionName - env exists: ' + !!env + ', type: ' + typeof env);
      if (env && typeof env.getOption === 'function') {
        const actionName = env.getOption('actionName') || '';
        log('getActionName - resolved actionName: ' + actionName);
        return actionName;
      }
      log('getActionName - env.getOption is not a function');
      return '';
    } catch (error) {
      logError('Error getting action name: ' + error);
      return '';
    }
  }

  function parseContextData(record) {
    try {
      log('parseContextData - record exists: ' + !!record);
      if (!record || typeof record.getContextData !== 'function') {
        log('parseContextData - getContextData not available');
        return {};
      }
      const contextData = record.getContextData();
      log('parseContextData - raw type: ' + typeof contextData);
      if (typeof contextData === 'string') {
        const parsed = JSON.parse(contextData);
        log('parseContextData - parsed from string, keys: ' + JSON.stringify(Object.keys(parsed)));
        return parsed;
      } else if (typeof contextData === 'object' && contextData !== null) {
        log('parseContextData - already object, keys: ' + JSON.stringify(Object.keys(contextData)));
        return contextData;
      } else {
        log('parseContextData - unexpected type, returning {}');
        return {};
      }
    } catch (error) {
      logError('Error parsing context data: ' + error);
      return {};
    }
  }

  function findFieldCaseInsensitive(obj, fieldName) {
    if (!obj || typeof obj !== 'object') return undefined;
    if (obj[fieldName] !== undefined) return obj[fieldName];
    const lowerField = fieldName.toLowerCase();
    for (const key of Object.keys(obj)) {
      if (key.toLowerCase() === lowerField) {
        log('findFieldCaseInsensitive - matched "' + key + '" for "' + fieldName + '"');
        return obj[key];
      }
    }
    return undefined;
  }

  function getFieldData(contextData, baseFieldName) {
    log('getFieldData - baseFieldName: ' + baseFieldName + ', contextData exists: ' + !!contextData);
    if (!contextData) return null;

    const webFieldName = baseFieldName + '.VisitId';
    if (contextData[webFieldName] !== undefined) {
      isWebPlatform = true;
      log('getFieldData - detected web platform via ' + webFieldName);
      return contextData[webFieldName];
    }

    if (contextData[baseFieldName] !== undefined) {
      log('getFieldData - found mobile field: ' + baseFieldName);
      return contextData[baseFieldName];
    }

    log('getFieldData - field not found in contextData');
    return null;
  }

  function getFieldValue(record, fieldName) {
    try {
      log('getFieldValue - fieldName: ' + fieldName);
      log('getFieldValue - record exists: ' + !!record + ', has stringValue: ' + !!(record && typeof record.stringValue === 'function'));

      if (record && typeof record.stringValue === 'function') {
        const value = record.stringValue(fieldName);
        log('getFieldValue - stringValue("' + fieldName + '"): ' + (value ? '"' + value.substring(0, 100) + '..." (len=' + value.length + ')' : 'null'));
        if (value) return value;

        const lowerFieldName = fieldName.charAt(0).toLowerCase() + fieldName.slice(1);
        const lowerValue = record.stringValue(lowerFieldName);
        log('getFieldValue - stringValue("' + lowerFieldName + '"): ' + (lowerValue ? '"' + lowerValue.substring(0, 100) + '..." (len=' + lowerValue.length + ')' : 'null'));
        if (lowerValue) return lowerValue;

        const fullLower = fieldName.toLowerCase();
        const fullLowerValue = record.stringValue(fullLower);
        log('getFieldValue - stringValue("' + fullLower + '"): ' + (fullLowerValue ? '"' + fullLowerValue.substring(0, 100) + '..." (len=' + fullLowerValue.length + ')' : 'null'));
        if (fullLowerValue) return fullLowerValue;
      }

      const contextData = parseContextData(record);
      log('getFieldValue - contextData keys: ' + JSON.stringify(Object.keys(contextData)));

      const directValue = findFieldCaseInsensitive(contextData, fieldName);
      if (directValue) {
        log('getFieldValue - found in contextData root: "' + String(directValue).substring(0, 100) + '"');
        return directValue;
      }

      if (contextData.ProviderVisit) {
        log('getFieldValue - checking contextData.ProviderVisit, keys: ' + JSON.stringify(Object.keys(contextData.ProviderVisit)));
        const pvValue = findFieldCaseInsensitive(contextData.ProviderVisit, fieldName);
        if (pvValue) {
          log('getFieldValue - found in contextData.ProviderVisit: "' + String(pvValue).substring(0, 100) + '"');
          return pvValue;
        }
      }

      if (contextData.Visit) {
        log('getFieldValue - checking contextData.Visit, keys: ' + JSON.stringify(Object.keys(contextData.Visit)));
        const visitValue = findFieldCaseInsensitive(contextData.Visit, fieldName);
        if (visitValue) {
          log('getFieldValue - found in contextData.Visit: "' + String(visitValue).substring(0, 100) + '"');
          return visitValue;
        }
      }

      log('getFieldValue - no value found for ' + fieldName);
      return null;
    } catch (error) {
      logError('Error getting field value for ' + fieldName + ': ' + error);
      return null;
    }
  }

  async function loadComplianceRules() {
    try {
      log('loadComplianceRules - querying ' + CONFIG.COMPLIANCE_RULE_OBJECT);
      const condition = await new ConditionBuilder_noNs(
        CONFIG.COMPLIANCE_RULE_OBJECT,
        new FieldCondition_noNs('Is_Active__c', '=', true)
      ).build();
      log('loadComplianceRules - condition built, executing query...');

      const rules = await db.noNs_query(
        CONFIG.COMPLIANCE_RULE_OBJECT,
        condition
      );
      log('loadComplianceRules - loaded ' + rules.length + ' active rules');
      rules.forEach(function (rule, i) {
        log('  Rule[' + i + ']: Name=' + rule.noNs_stringValue('Name__c') + ', Type=' + rule.noNs_stringValue('Rule_Type__c') + ', Target=' + rule.noNs_stringValue('Target_Object__c') + '.' + rule.noNs_stringValue('Target_Field__c') + ', Action=' + rule.noNs_stringValue('Action__c'));
      });
      return rules;
    } catch (error) {
      logError('Error loading compliance rules: ' + error);
      return [];
    }
  }

  function getApplicableRules(allRules, objectType, fieldName) {
    const filtered = allRules.filter(function (rule) {
      const targetObject = rule.noNs_stringValue('Target_Object__c');
      const targetField = rule.noNs_stringValue('Target_Field__c');
      return targetObject === objectType && targetField === fieldName;
    });
    log('getApplicableRules - ' + filtered.length + '/' + allRules.length + ' rules match ' + objectType + '.' + fieldName);
    return filtered;
  }

  function validateKeywords(text, keywords) {
    log('validateKeywords - keywords: ' + keywords + ', text length: ' + (text ? text.length : 0));
    if (!keywords) return { matched: false, matchedTerms: [] };

    const lowerText = text.toLowerCase();
    const keywordList = keywords
      .split(',')
      .map(function (k) { return k.trim().toLowerCase(); })
      .filter(function (k) { return k; });
    log('validateKeywords - checking ' + keywordList.length + ' keywords: ' + JSON.stringify(keywordList));

    const matchedTerms = [];
    for (const keyword of keywordList) {
      if (lowerText.includes(keyword)) {
        matchedTerms.push(keyword);
      }
    }

    log('validateKeywords - matched: ' + (matchedTerms.length > 0) + ', matchedTerms: ' + JSON.stringify(matchedTerms));
    return {
      matched: matchedTerms.length > 0,
      matchedTerms: matchedTerms,
    };
  }

  function validatePattern(text, pattern) {
    log('validatePattern - pattern: ' + pattern + ', text length: ' + (text ? text.length : 0));
    if (!pattern) return { matched: false, matchedText: null };

    try {
      const regex = new RegExp(pattern, 'i');
      const match = text.match(regex);
      log('validatePattern - matched: ' + (match !== null) + ', matchedText: ' + (match ? match[0] : null));
      return {
        matched: match !== null,
        matchedText: match ? match[0] : null,
      };
    } catch (error) {
      logError('Invalid regex pattern: ' + pattern + ' - ' + error);
      return { matched: false, matchedText: null };
    }
  }

  function validateRule(text, rule) {
    const ruleName = rule.noNs_stringValue('Name__c');
    const ruleType = rule.noNs_stringValue('Rule_Type__c');
    const keywords = rule.noNs_stringValue('Keywords__c');
    const pattern = rule.noNs_stringValue('Pattern__c');

    log('validateRule - evaluating "' + ruleName + '" (type=' + ruleType + ')');

    let result;
    if (ruleType === 'Keyword_Match') {
      result = validateKeywords(text, keywords);
    } else if (ruleType === 'Pattern_Match') {
      result = validatePattern(text, pattern);
    } else {
      log('validateRule - unknown rule type: "' + ruleType + '"');
      result = { matched: false };
    }

    log('validateRule - "' + ruleName + '" result: matched=' + result.matched);
    return result;
  }

  function extractExcerpt(text, matchedContent, contextLength) {
    contextLength = contextLength || 50;
    if (!text || !matchedContent) return '';

    const lowerText = text.toLowerCase();
    const matchTerm = Array.isArray(matchedContent)
      ? matchedContent[0]
      : matchedContent;
    const lowerMatch = matchTerm.toLowerCase();
    const matchIndex = lowerText.indexOf(lowerMatch);

    if (matchIndex < 0) return '';

    const startIndex = Math.max(0, matchIndex - contextLength);
    const endIndex = Math.min(
      text.length,
      matchIndex + matchTerm.length + contextLength
    );

    let excerpt = text.substring(startIndex, endIndex);

    if (startIndex > 0) {
      const spaceIndex = excerpt.indexOf(' ');
      if (spaceIndex > 0) excerpt = excerpt.substring(spaceIndex + 1);
    }

    if (endIndex < text.length) {
      const spaceIndex = excerpt.lastIndexOf(' ');
      if (spaceIndex > 0) excerpt = excerpt.substring(0, spaceIndex);
    }

    return excerpt.trim();
  }

  function buildErrorMessage(rule, matchedContent, originalText) {
    const ruleName = rule.noNs_stringValue('Name__c');
    const severity = rule.noNs_stringValue('Severity__c');
    const remediation = rule.noNs_stringValue('Remediation_Message__c');
    const matchStr = Array.isArray(matchedContent)
      ? matchedContent.join(', ')
      : matchedContent;
    const excerpt = extractExcerpt(originalText, matchedContent);

    const parts = [];
    parts.push('❌ ' + ruleName + ' - ' + severity);
    parts.push('');
    parts.push('Found: "' + matchStr + '" in your text');
    parts.push('');

    if (excerpt) {
      parts.push('Text excerpt: "...' + excerpt + '..."');
      parts.push('');
    }

    parts.push('Action required: ' + remediation);
    return parts.join('\n');
  }

  async function validateVisit() {
    try {
      log('========== validateVisit START ==========');
      log('env exists: ' + (typeof env !== 'undefined' && !!env));
      log('record exists: ' + (typeof record !== 'undefined' && !!record));
      log('user exists: ' + (typeof user !== 'undefined' && !!user));
      log('db exists: ' + (typeof db !== 'undefined' && !!db));

      const actionName = getActionName(env);
      const shouldValidate = [
        'Submit',
        'Sign',
        'runCustomScriptValidations',
      ].includes(actionName);

      log('actionName: ' + actionName + ', shouldValidate: ' + shouldValidate);

      if (!shouldValidate) {
        log('Skipping validation for action: ' + actionName);
        return [{ title: 'Validation skipped for this action', status: 'success' }];
      }

      log('Starting compliance validation...');

      const allRules = await loadComplianceRules();
      if (allRules.length === 0) {
        log('WARN: No compliance rules found');
        return [{ title: 'No compliance rules configured', status: 'success' }];
      }

      const results = [];

      for (const fieldName of CONFIG.TARGET_FIELDS) {
        log('--- Processing field: ' + fieldName + ' ---');
        const fieldValue = getFieldValue(record, fieldName);

        if (!fieldValue) {
          log('Field ' + fieldName + ' has no value, skipping');
          continue;
        }
        if (fieldValue.trim().length < CONFIG.MIN_TEXT_LENGTH) {
          log('Field ' + fieldName + ' too short: ' + fieldValue.trim().length + ' < ' + CONFIG.MIN_TEXT_LENGTH + ', skipping');
          continue;
        }

        log('Validating field: ' + fieldName + ', value: "' + fieldValue.substring(0, 200) + '"');

        const applicableRules = getApplicableRules(
          allRules,
          'ProviderVisit',
          fieldName
        );
        if (applicableRules.length === 0) {
          log('No rules for field: ' + fieldName);
          continue;
        }

        for (const rule of applicableRules) {
          const ruleResult = validateRule(fieldValue, rule);

          if (ruleResult.matched) {
            const action = rule.noNs_stringValue('Action__c');
            const matchedContent =
              ruleResult.matchedTerms || ruleResult.matchedText;
            log('Rule violated: ' + rule.noNs_stringValue('Name__c') + ', action: ' + action + ', matchedContent: ' + JSON.stringify(matchedContent));

            const errorMessage = buildErrorMessage(
              rule,
              matchedContent,
              fieldValue
            );

            if (action === 'Block') {
              results.push({ title: errorMessage, status: 'error' });
            } else if (action === 'Warn') {
              results.push({ title: errorMessage, status: 'warning' });
            }

            await queueAuditLog(rule, fieldValue, ruleResult);
          }
        }
      }

      log('Validation complete. Total results: ' + results.length);
      log('Results: ' + JSON.stringify(results.map(function (r) { return { status: r.status, titlePreview: r.title.substring(0, 80) }; })));

      if (results.length === 0) {
        log('Compliance validation passed - no violations');
        return [
          { title: '✓ Visit complies with all validation rules', status: 'success' },
        ];
      }

      log('========== validateVisit END ==========');
      return results;
    } catch (error) {
      logError('Error in compliance validation: ' + error);
      logError('Error stack: ' + (error.stack || 'no stack'));
      return [
        {
          title: 'Error in validation: ' + error.message,
          status: 'error',
          error: error.message,
        },
      ];
    }
  }

  async function queueAuditLog(rule, fieldValue, validationResult) {
    try {
      log('queueAuditLog - building audit entry for rule: ' + rule.noNs_stringValue('Name__c'));
      const auditLogData = {
        Rule__c: rule.noNs_stringValue('Id'),
        Record_Id__c: record.stringValue('Id'),
        Record_Type__c: 'ProviderVisit',
        Validation_Result__c: validationResult.matched ? 'Fail' : 'Pass',
        User__c: user.stringValue('Id'),
        Timestamp__c: new Date().toISOString(),
        Details__c: JSON.stringify({
          matched_content:
            validationResult.matchedTerms || validationResult.matchedText,
          field_value_length: fieldValue.length,
          execution_mode: isWebPlatform ? 'web' : 'mobile',
        }),
      };
      log('queueAuditLog - data: ' + JSON.stringify(auditLogData));
    } catch (error) {
      logError('Error queueing audit log: ' + error);
    }
  }

  log('Invoking validateVisit...');
  const validationResults = validateVisit();
  log('validateVisit returned, isArray: ' + Array.isArray(validationResults));
  return Array.isArray(validationResults)
    ? validationResults
    : [validationResults];
})();
