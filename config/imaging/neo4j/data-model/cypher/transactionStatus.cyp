MATCH(t:Transaction:`ApplicationName`)-[r:TRANSACTION_STARTPOINT]->(o:Object)
SET o.transactionStatus = 'start';

MATCH(t:Transaction:`ApplicationName`)-[r:TRANSACTION_ENDPOINT]->(o:Object)
SET o.transactionStatus = 'end';