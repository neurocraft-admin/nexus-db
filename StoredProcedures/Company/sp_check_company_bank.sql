-- The bank and payment fields of the profile document (see sp_check_company_profile).
--   22023 invalid parameter - the first field that is wrong (COLUMN names it)
CREATE OR REPLACE PROCEDURE sp_check_company_bank(p_profile jsonb)
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_assert_company_text(p_profile, 'bankAccountName', 150);
    CALL sp_assert_company_text(p_profile, 'bankName', 150);
    CALL sp_assert_company_text(p_profile, 'bankBranch', 150);
    CALL sp_assert_company_format(p_profile, 'bankAccountNumber', '^[0-9]{6,30}$', 'An account number is 6 to 30 digits');
    CALL sp_assert_company_format(p_profile, 'bankIfsc', '^[A-Z]{4}0[A-Z0-9]{6}$', 'An IFSC is 4 letters, a 0 and 6 letters or digits, for example SBIN0001234', true);
    CALL sp_assert_company_format(p_profile, 'upiId', '^[A-Za-z0-9._-]{2,64}@[A-Za-z]{2,64}$', 'A UPI id looks like name@bank');
    CALL sp_assert_company_text(p_profile, 'upiId', 100);
    CALL sp_assert_company_text(p_profile, 'otherPaymentDetails', 1000);
END;
$$;
