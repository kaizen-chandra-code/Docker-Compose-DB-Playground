print("Open ticket queue");
printjson(app.getCollection("demo_support_tickets")
    .find({status: "open"}, {subject: 1, priority: 1})
    .sort({priority: -1, _id: 1}).toArray());

print("Open tickets with an agent reply");
printjson(app.getCollection("demo_support_tickets").find({
    status: "open", events: {$elemMatch: {kind: "replied", actor: "agent"}}
}, {subject: 1, events: 1}).sort({_id: 1}).toArray());
