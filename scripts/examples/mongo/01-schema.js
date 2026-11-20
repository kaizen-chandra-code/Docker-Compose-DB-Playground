app.getCollection("demo_support_tickets").createIndex(
    {status: 1, priority: -1, _id: 1},
    {name: "support_queue"}
);
