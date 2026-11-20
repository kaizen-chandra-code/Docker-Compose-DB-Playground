const tickets = [
    {
        _id: "ticket-001", subject: "Package arrived open", status: "open", priority: 3,
        events: [{kind: "created", actor: "customer"}, {kind: "replied", actor: "agent"}]
    },
    {
        _id: "ticket-002", subject: "Update delivery address", status: "open", priority: 1,
        events: [{kind: "created", actor: "customer"}], delivery: {country: "IN"}
    },
    {
        _id: "ticket-003", subject: "Refund confirmation", status: "closed", priority: 3,
        events: [{kind: "created", actor: "customer"}, {kind: "closed", actor: "agent"}]
    }
];
for (const ticket of tickets) {
    const {_id, ...fields} = ticket;
    app.getCollection("demo_support_tickets").updateOne(
        {_id}, {$setOnInsert: fields}, {upsert: true}
    );
}
