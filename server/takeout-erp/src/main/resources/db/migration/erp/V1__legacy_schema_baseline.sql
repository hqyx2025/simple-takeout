-- The document-number upgrade must have completed before this version is recorded.
SELECT id, document_no FROM erp_purchases WHERE 1 = 0;
SELECT id, document_no FROM erp_receipts WHERE 1 = 0;
SELECT id, document_no FROM erp_payments WHERE 1 = 0;
