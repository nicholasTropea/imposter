export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.1"
  }
  public: {
    Tables: {
      game_words: {
        Row: {
          game_id: string
          id: string
          player_id: string
          round_number: number
          word: string | null
        }
        Insert: {
          game_id: string
          id?: string
          player_id: string
          round_number: number
          word?: string | null
        }
        Update: {
          game_id?: string
          id?: string
          player_id?: string
          round_number?: number
          word?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "game_words_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "ranked_games"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "game_words_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
        ]
      }
      players: {
        Row: {
          civilian_wins: number
          elo: number
          id: string
          imposter_wins: number
          nickname: string
          played_games: number
          spy_wins: number
        }
        Insert: {
          civilian_wins?: number
          elo?: number
          id?: string
          imposter_wins?: number
          nickname: string
          played_games?: number
          spy_wins?: number
        }
        Update: {
          civilian_wins?: number
          elo?: number
          id?: string
          imposter_wins?: number
          nickname?: string
          played_games?: number
          spy_wins?: number
        }
        Relationships: []
      }
      ranked_game_players: {
        Row: {
          game_id: string
          joined_at: string | null
          last_seen: string | null
          role: string | null
          user_id: string
          word: string | null
        }
        Insert: {
          game_id: string
          joined_at?: string | null
          last_seen?: string | null
          role?: string | null
          user_id: string
          word?: string | null
        }
        Update: {
          game_id?: string
          joined_at?: string | null
          last_seen?: string | null
          role?: string | null
          user_id?: string
          word?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ranked_game_players_game_id_fkey"
            columns: ["game_id"]
            isOneToOne: false
            referencedRelation: "ranked_games"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ranked_game_players_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
        ]
      }
      ranked_games: {
        Row: {
          active_player_id: string | null
          created_at: string | null
          id: string
          max_players: number
          phase: string
          phase_deadline: string | null
          player_count: number
          round_number: number
          status: string
          turn_index: number
          turn_order: string[]
          words_id: number
        }
        Insert: {
          active_player_id?: string | null
          created_at?: string | null
          id?: string
          max_players?: number
          phase?: string
          phase_deadline?: string | null
          player_count?: number
          round_number?: number
          status?: string
          turn_index?: number
          turn_order?: string[]
          words_id: number
        }
        Update: {
          active_player_id?: string | null
          created_at?: string | null
          id?: string
          max_players?: number
          phase?: string
          phase_deadline?: string | null
          player_count?: number
          round_number?: number
          status?: string
          turn_index?: number
          turn_order?: string[]
          words_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "ranked_games_active_player_id_fkey"
            columns: ["active_player_id"]
            isOneToOne: false
            referencedRelation: "players"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ranked_games_words_id_fkey"
            columns: ["words_id"]
            isOneToOne: false
            referencedRelation: "words"
            referencedColumns: ["id"]
          },
        ]
      }
      settings: {
        Row: {
          daily_rewards: boolean
          game_invites: boolean
          master_volume: number
          music_volume: number
          sound_effects: boolean
          theme: Database["public"]["Enums"]["theme_type"]
          user_id: string
        }
        Insert: {
          daily_rewards?: boolean
          game_invites?: boolean
          master_volume?: number
          music_volume?: number
          sound_effects?: boolean
          theme?: Database["public"]["Enums"]["theme_type"]
          user_id: string
        }
        Update: {
          daily_rewards?: boolean
          game_invites?: boolean
          master_volume?: number
          music_volume?: number
          sound_effects?: boolean
          theme?: Database["public"]["Enums"]["theme_type"]
          user_id?: string
        }
        Relationships: []
      }
      words: {
        Row: {
          civilian_word: string
          id: number
          imposter_word: string
        }
        Insert: {
          civilian_word: string
          id?: number
          imposter_word: string
        }
        Update: {
          civilian_word?: string
          id?: number
          imposter_word?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      advance_turn: { Args: { p_game_id: string }; Returns: undefined }
      join_or_create_ranked_game: {
        Args: { p_user_id: string }
        Returns: string
      }
    }
    Enums: {
      theme_type: "dark" | "light"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      theme_type: ["dark", "light"],
    },
  },
} as const
