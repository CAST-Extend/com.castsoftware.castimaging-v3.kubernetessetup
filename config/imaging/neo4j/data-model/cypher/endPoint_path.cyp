MATCH (o:Object) WHERE o.transactionStatus CONTAINS "end"
SET o.badgeIcon = './img/exit-point.svg';