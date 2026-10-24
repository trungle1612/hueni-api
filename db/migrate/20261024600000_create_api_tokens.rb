# Mini App sign-in (#152): bearer tokens, kept only as a SHA-256 digest.
class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false, index: { unique: true }
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.string :user_agent
      t.timestamps
    end
  end
end
