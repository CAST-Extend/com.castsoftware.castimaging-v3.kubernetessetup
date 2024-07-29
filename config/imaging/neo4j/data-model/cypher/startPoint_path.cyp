MATCH (o:Object) WHERE o.transactionStatus CONTAINS "start"
SET o.badgeIcon = './img/entry-point.svg';