/// <reference path="../pb_data/types.d.ts" />

// Creates the one collection every Baselit app syncs through (PocketBase 0.23 or newer).
// Each row is one house, location, container, item, photo, or home location, stored
// as its Baselit backup JSON in `data`. Rows are only visible to the user who owns them.
// Row IDs are the records' own lowercase UUIDs, so every device agrees on them.
migrate(
  (app) => {
    const users = app.findCollectionByNameOrId("users");
    const mine = "owner = @request.auth.id";

    const collection = new Collection({
      type: "base",
      name: "baselit_records",
      listRule: mine,
      viewRule: mine,
      createRule: "@request.auth.id != '' && @request.body.owner = @request.auth.id",
      updateRule: mine + " && (@request.body.owner:isset = false || @request.body.owner = @request.auth.id)",
      deleteRule: mine,
      fields: [
        {
          name: "id",
          type: "text",
          system: true,
          primaryKey: true,
          required: true,
          min: 36,
          max: 36,
          pattern: "^[a-z0-9-]+$",
          autogeneratePattern: "",
        },
        {
          name: "owner",
          type: "relation",
          required: true,
          collectionId: users.id,
          maxSelect: 1,
          cascadeDelete: true,
        },
        {
          name: "kind",
          type: "select",
          required: true,
          maxSelect: 1,
          values: ["house", "location", "container", "item", "photo", "homeLocation"],
        },
        { name: "data", type: "json", maxSize: 1000000 },
        { name: "deleted", type: "bool" },
        {
          name: "photo",
          type: "file",
          maxSelect: 1,
          maxSize: 52428800,
          protected: true,
        },
        { name: "created", type: "autodate", onCreate: true, onUpdate: false },
        { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
      ],
      indexes: ["CREATE INDEX idx_baselit_records_owner_updated ON baselit_records (owner, updated)"],
    });

    app.save(collection);
  },
  (app) => {
    app.delete(app.findCollectionByNameOrId("baselit_records"));
  },
);
